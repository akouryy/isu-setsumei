#!ruby -W:no-experimental

require 'optparse'
require 'shellwords'
require 'tempfile'

class Array
  def soft_transpose
    Array.new(map(&:size).max){|i| map{|e| e[i] } }
  end
end

class Config
  ALWAYS = :always
  AUTO = :auto
  NEVER = :never
  COLORS = [ALWAYS, AUTO, NEVER].freeze

  attr_writer :v_num, :v_limit, :v_offset, :v_str, :v_like,
              :v_upper_bound, :v_lower_bound, :output_queries, :compact
  attr_accessor :ban

  def initialize
    self.v_num = 1
    self.v_limit = nil
    self.v_offset = nil
    self.v_str = 'a%a'
    self.v_like = nil
    self.output_queries = false
    self.color = AUTO
    self.ban = /\bfilesort\b/
    @specials = {}
  end

  def verbose?; $VERBOSE end

  def verbose= v; $VERBOSE = v end

  def num; @v_num end

  def limit; @v_limit || num end

  def offset; @v_offset || num end

  def str; @v_str end

  def like; @v_like || str end

  def upper_bound; @v_upper_bound || num + 500 end

  def lower_bound; @v_lower_bound || num end

  def output_queries?; @output_queries end

  def compact?; @compact end

  def color?
    @color == ALWAYS || @color == AUTO && $stdout.tty?
  end

  def color= v
    raise v.to_s unless COLORS.include? v
    @color = v
  end

  def special r, c
    debug @specials if r == 0 && c == 0
    @specials[[r, c]]
  end

  def add_special r, c, v
    @specials[[r, c]] = v
  end
end

$conf = Config.new

def warn str
  Kernel.warn "WARNING: #{str}"
end

def debug str
  $stderr.puts "DEBUG: #{str}" if $conf.verbose?
end

def option_parser
  OptionParser.accept Regexp do |s|
    Regexp.new s rescue raise OptionParser::InvalidArgument, s
  end

  opt = OptionParser.new

  opt.on '-n', '--number NUM', Integer, 'Set a replacement value for number placeholders' do |n|
    $conf.v_num = n
  end

  opt.on '-l', '--limit NUM', Integer, 'Specify a replacement value for LIMIT placeholders' do |n|
    $conf.v_limit = n
  end

  opt.on '-o', '--offset NUM', Integer, 'Specify a replacement value for OFFSET placeholders' do |n|
    $conf.v_offset = n
  end

  opt.on '-U', '--upper-bound NUM', Integer, 'Specify a replacement value for upper bound placeholders' do |n|
    $conf.v_upper_bound = n
  end

  opt.on '-L', '--lower-bound NUM', Integer, 'Specify a replacement value for lower bound placeholders' do |n|
    $conf.v_lower_bound = n
  end

  opt.on '-s', '--string STR', 'Set a replacement value for string placeholders' do |s|
    $conf.v_str = s
  end

  opt.on '-k', '--like STR', 'Specify a replacement value for LIKE placeholders' do |s|
    $conf.v_like = s
  end

  opt.on '-c', '--color WHEN', Config::COLORS,
         'Specify when to highlight words; ' +
         'WHEN can be `auto` (default), `always`, or `never`' do |s|
    $conf.color = s
  end

  opt.on '-b', '--ban REGEXP', Regexp, 'Set the pattern for highlighting results' do |r|
    $conf.ban = r
  end

  opt.on '-q', '--query', 'Output EXPLAIN queries' do |b|
    raise OptionParser::InvalidArgument, b unless b
    $conf.output_queries = true
  end

  opt.on '-a', '--add-special ROW,COL,VAL',
         /\A \s* (\d+) \s* , \s* (\d+) \s* , (.+) \z/x,
         'Specify a special replacement value for one placeholder' do |_, r, c, v|

    $conf.add_special r.to_i, c.to_i, v
  end

  opt.on '-z', '--zip', 'Output compactly' do |b|
    raise OptionParser::InvalidArgument, b unless b
    $conf.compact = true
  end

  opt.on '-v', '--verbose', 'Output more debug messages' do |b|
    raise OptionParser::InvalidArgument, b unless b
    $conf.verbose = true
  end

  opt.banner += <<~BANNER
    \ [slow_query_files]

    parameters:
        [slow_query_files]      If specified, read logs from them. Otherwise, use STDIN instead.
    environment variables:
        MYSQL_HOST              MySQL host
        MYSQL_PORT              MySQL port
        MYSQL_USER              MySQL user name
        MYSQL_PASS              MySQL password
        MYSQL_DBNAME            MySQL database name
    options:
  BANNER
  opt.version = [1, 0, 0]

  opt
end

def fill_placeholders stmt, row
  col = 0
  stmt.gsub %r[
    (?<prefix_sp>
      (?<prefix> \b LIMIT | \b OFFSET )
      \s+
    |
      (?<prefix> [<>] =?) # comparison
      \s*
    )
    (?<holder> \b N \b)
  |
    (?<holder> \b N \b)
    (?<postfix_sp>
      \s*
      (?<postfix> [<>] =?) # comparison
    )?
  |
    (?<prefix_sp>
      (
        (?<prefix> \b LIKE )
        \s*
      )?
      \' # a quote is required
    )
    (?<holder> \b S \b)
  ]ix do
    debug "special(#{row}, #{col}) => #{$conf.special(row, col).inspect}"
    debug $~.inspect

    fill =
      $conf.special(row, col) ||
        case [$~[:prefix], $~[:postfix]]
        in ['LIMIT', _]                      then $conf.limit.to_s
        in ['OFFSET', _]                     then $conf.offset.to_s
        in ['LIKE', _]                       then $conf.like
        in ['<' | '<=', _] | [_, '>' | '>='] then $conf.upper_bound.to_s
        in ['>' | '>=', _] | [_, '<' | '<='] then $conf.lower_bound.to_s
        in [nil, nil]
          case $~[:holder]
          in 'N' then $conf.num.to_s
          in 'S' then $conf.str
          end
        end

    col += 1

    [$~[:prefix_sp], fill, $~[:postfix_sp]].join
  end
end

def generate_explain_query
  debug 'Reading from stdin...' if ARGV.empty?

  statements = gets(nil).split("\n\n").map.with_index do |entry, row|
    next if entry !~ /\S/

    header, *stmt = entry.lines(chomp: true).grep_v ''

    raise [:invalid_header, /^Count/, entry].inspect if header !~ /^Count/

    fill_placeholders stmt.join, row
  end

  raise [:empty_log, statements].inspect if statements.empty?

  query = statements.map{ "EXPLAIN #{_1};".split.join ' ' }.join "\n"

  if $conf.output_queries?
    puts query.lines.map.with_index{ "[#{_2}] #{_1}" }
    puts
  else
    debug query.delete "\n"
  end

  query
end

def execute_explain query
  host = ENV.fetch 'MYSQL_HOST', '127.0.0.1'
  port = ENV.fetch 'MYSQL_PORT', '3306'
  user = ENV.fetch 'MYSQL_USER', 'isucon'
  pass = ENV.fetch 'MYSQL_PASS', 'isucon'
  dbname = ENV.fetch 'MYSQL_DBNAME', 'isuumo'

  # query = Shellwords.shellescape query

  File.write 'setsumei-query.txt', query
  debug "mysql -h#{host} -P#{port} -u#{user} -p#{pass} #{dbname} < setsumei-query.txt"
  res = `mysql -h#{host} -P#{port} -u#{user} -p#{pass} #{dbname} < setsumei-query.txt`
  if $?.exitstatus != 0
    $stderr.puts "\e[1;31mERROR\e[0m: mysql process returns #{$?.inspect}"
  else
    debug $?.inspect
  end
  res
end

def format_response res
  i = -1

  table = res.lines.map do |l|
    if l =~ /^id\b/
      i += 1
      if i == 0
        if $conf.compact?
          l = l.sub(/^id\b/, '#')
               .sub(/\bselect_type\b/, 'sel.')
               .sub(/\bpartitions\b/, 'p.')
               .sub(/\bkey_len\b/, 'k.')
               .sub(/\bfiltered\b/, 'f.')
        end
        ["", *l.chomp.split("\t")]
      end
    else
      if $conf.compact?
        l = l.gsub(/\bNULL\b/, "\0\0")
             .gsub(/\bUsing /, "\1")
             .gsub(/\b\.00\b/, "\2")
      end
      ["[#{i}]", *l.chomp.split("\t")]
    end
  end.compact

  sizes = table.soft_transpose.map{|col| col.compact.map(&:size).max }

  uncolored = table.map do |row|
    row.zip(sizes).map do |c, s|
      c.ljust s
    end.join(' ').rstrip
  end.join "\n"

  if $conf.compact?
    uncolored =
      "#: id, sel.: select_type, p.: partitions, k.: key_len, f.: filtered; " +
      "\0\0: NULL, \1: Using, \2: .00\n\n" +
      uncolored
  end

  if $conf.color?
    uncolored.gsub($conf.ban, "\e[1;31m\\&\e[0m")
             .gsub("\0\0", "\e[90m--\e[0m")
             .gsub("\1", "\e[36mU\e[0m")
             .gsub("\2", "\e[90m/\e[0m")
             .gsub(/^(\S++ ++){6}\S*\b\K(\w++)\b(?=\S*+ ++\2\b)/, "\e[36m\\&\e[0m")
  else
    uncolored.gsub("\0\0", '--')
             .gsub("\1", 'U')
             .gsub("\2", '/')
  end
end

begin
  option_parser.permute! ARGV

  puts format_response execute_explain generate_explain_query

rescue => err
  $stderr.puts err.full_message
  puts

  puts option_parser.help
  exit 10
end
