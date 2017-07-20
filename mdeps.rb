#!/usr/bin/ruby

require 'optparse'
require 'set'

$DevNull = File.open(File::NULL, mode="w")

class DepPattern
  attr_reader :group_globbed
  attr_reader :artifact_globbed

  def initialize(raw)
    if raw.include?(',')
      raise "Patterns may not contain ','. Illegal pattern: '#{raw}'" 
    end

    if raw.count(':') == 0 or (raw.end_with?(':') and raw.count(':') == 1)
      @group_globbed = raw
      @artifact_globbed = raw
      @both_specified = false
    elsif raw.count(':') == 1 or (raw.end_with?(':') and raw.count(':') == 2)
      split = raw.split(':')
      @group_globbed = split[0]
      @artifact_globbed = split[1]
      @both_specified = true
    else
      raise "Bad dep pattern: '#{raw}'"
    end
  end

  def match(dep)
    if (@both_specified)
      return File.fnmatch(group_globbed, dep.group) && File.fnmatch(artifact_globbed, dep.artifact)
    else
      return File.fnmatch(group_globbed, dep.group) || File.fnmatch(artifact_globbed, dep.artifact)
    end
  end

  def to_mvn_patterns()
    if (@both_specified)
      return ["#{group_globbed}:#{artifact_globbed}"]
    else
      return ["#{group_globbed}:#{artifact_globbed}", "#{group_globbed}:*", "*:#{artifact_globbed}"]
    end
  end
end

class Dep
  attr_reader :group
  attr_reader :artifact
  attr_reader :version

  def initialize(group, artifact, version)
    @group = group
    @artifact = artifact
    @version = version
  end

  def label()
    return "#{@group}<BR/>#{@artifact}<BR/>#{@version}"
  end

  def node()
    return "#{@group}_#{@artifact}_#{@version}"
  end

  def eql?(other)
    return node().eql? other.node()
  end

  def hash()
    return node().hash
  end
end

class DepRelation
  attr_reader :depender
  attr_reader :depended

  def initialize(depender, depended)
    @depender = depender
    @depended = depended
  end

  def eql?(other)
    return @depender.eql?(other.depender()) &&
      @depended.eql?(other.depended())
  end
  
  def hash()
    return @depender.hash() ^ @depended.hash()
  end
end

options = {
  :debug_out => $DevNull,
  :browser => 'google-chrome',
  :excluded_scopes => ["compile", "runtime"],
  :mvn_verbose => false,
  :fmt => "svg",
  :output => nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: mdep [options] [patterns]..."

  opts.on("-b", "--browser BROWSER", "") do |b|
    options[:browser] = b
  end

  opts.on("-o", "--output-file", "") do |o|
    if o == '-'
      options[:output] = STDOUT
    else
      options[:output] = File.open(o, mode="w+")
    end
  end

  opts.on("-f", "--output-format FORMAT", "") do |f|
    unless ["svg", "pdf", "png"].member?(f)
      raise "Unknown output format: '#{f}'"
    end
    
    options[:fmt] = f
  end

  opts.on("--scopes compile,runtime,test", Array, "Dependence scopes to include. Default: compile, runtime") do |s|
    options[:scopes] = ["compile","provided","runtime","test", "system", "import"] - s
  end
  
  opts.on("-d", "--[no-]debug", "Print debug output") do |d|
    if d
      options[:debug_out] = STDERR
    else
      options[:debug_out] = $DevNull
    end
  end

  opts.on("-v", "--[no-]mvn-verbose", "Invoke maven with verbose=true") do |v|
    options[:mvn_verbose] = v
  end
  
end.parse!

mvn_out = `mktemp`.chomp
patterns = ARGV.map { |p| DepPattern.new(p) }
call_patterns = patterns.flat_map { |p| p.to_mvn_patterns }.join(",")
excludes = options[:excluded_scopes].map {|s| "::::#{s}"}.join(',')

mvn_result = system("mvn", "dependency:tree", "-DoutputType=dot", "-Dverbose=#{options[:mvn_verbose]}",
                    "-DoutputFile=#{mvn_out}", "-DappendOutput=true",
                    "-Dincludes=#{call_patterns}", "-Dexcludes=#{excludes}",
                    :err => options[:debug_out], :out => options[:debug_out])

if (mvn_result.nil?)
  STDERR.puts "Failed to exec mvn: #{$!}" 
  exit 1
elsif (!mvn_result)
  STDERR.puts "mvn run failed"
  exit 2
end

roots = Set.new
nodes = Set.new
edges = Set.new

root_re = /digraph "([^:]+):([^:]+):([^:]+):([^:]+)(:[^:]+)?"/
edge_re = /"([^:]+):([^:]+):([^:]+):([^:]+)(:[^:]+)?"\s+->\s+"([^:]+):([^:]+):([^:]+):([^:]+)(:[^:]+)?"/

File.readlines(mvn_out).each do |line|
  if (m = root_re.match line)
    c = m.captures
    roots << Dep.new(c[0], c[1], c[3])
  elsif (m = edge_re.match line)
    c = m.captures
    depender = Dep.new(c[0], c[1], c[3])
    depended = Dep.new(c[5], c[6], c[8])

    nodes << depender
    nodes << depended
    edges << DepRelation.new(depender, depended)
  end
end

dot_file = File.open(`mktemp`.chomp, mode="w+")
dot_file.write(%Q$digraph "deps" {\n$)

roots.each do |root|
  dot_file.write(%Q$  "#{root.node}" [fillcolor=black shape=box fontcolor=white style=filled label=<#{root.label}>];\n$)
end

(nodes - roots).each do |node|
  if patterns.any? { |p| p.match(node) }
    options[:debug_out].write("Node matches pattern: #{node.node()}\n")
    dot_file.write(%Q$  "#{node.node}" [fillcolor=gold style=filled shape=box label=<#{node.label}>];\n$)
  else
    options[:debug_out].write("Node does not match pattern: #{node.node()}\n")
    dot_file.write(%Q$  "#{node.node}" [shape=box label=<#{node.label}>];\n$)
  end
end

edges.each do |edge|
  dot_file.write(%Q$  "#{edge.depender.node}" -> "#{edge.depended.node}";\n$)
end

dot_file.write("}\n")
dot_file.close()

File.open(dot_file.path, mode="r") do |f|
  options[:debug_out].write("dot file:\n")
  IO.copy_stream(f, options[:debug_out])
end

output_path = nil
File.open(options[:output] || `mktemp XXXXXXX.#{options[:fmt]}`.chomp, mode="w+") do |output|
  dot_result = system("dot -G'nodesep=0.1' -G'ranksep=0.02' -G'dpi=50' -G'ratio=0.56' #{dot_file.path} | unflatten -l10 -f -c3 | dot -T#{options[:fmt]}",
                      :out => output, :err => options[:debug_out]) 

  if (dot_result.nil?)
    STDERR.puts "Failed to exec dot: #{$!}" 
    exit 1
  elsif (!dot_result)
    STDERR.puts "dot run failed"
    exit 2
  end

  output_path = output.path
end

system(options[:browser], output_path, :err => options[:debug_out], :out => options[:debug_out])
