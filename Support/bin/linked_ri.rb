#!/usr/bin/env ruby -w
# encoding: utf-8

# if we are not called directly from TM (e.g. JavaScript) the caller
# should ensure that RUBYLIB is set properly
$: << "#{ENV["TM_SUPPORT_PATH"]}/lib" if ENV.has_key? "TM_SUPPORT_PATH"
LINKED_RI = "#{ENV["TM_BUNDLE_SUPPORT"]}/bin/linked_ri.rb"

require "exit_codes"
require "ui"
require "web_preview"

require "erb"
include ERB::Util

RI_EXE = [ ENV['TM_RUBY_RI'], 'ri', 'qri' ].find { |cmd| !cmd.to_s.empty? && (File.executable?(cmd) || ENV['PATH'].split(':').any? { |dir| File.executable? File.join(dir, cmd) }) ? cmd : false }

term = ARGV.shift

# first escape for use in the shell, then escape for use in a JS string
def e_js_sh(str)
  (e_sh str).gsub("\\", "\\\\\\\\")
end

def link_methods(prefix, methods)
  methods.sub(/^\n  /,'').split("\n  ").map do |match|
    "<a href=\"javascript:ri('#{prefix}#{match}')\">#{match}</a>"
  end.join(', ')
end

def htmlize_ri_output(text, term)
  text = text.gsub(/&/, '&amp;').gsub(/<([^\/t]{2})/, "&lt;\\1")

  text.gsub!(/^(\(from[^\n]+\n-----+\n)([^=].*?)(?=\n(\(from)|(\n-----+\n=)|\Z)/m, "\\1\n<pre>\n\\2\n</pre>\n")
    
  text.sub!(/\A= ([^.#\n]*)$\n*/) do
    "<h2>Class: " + $1.gsub(/([A-Z_]\w*)(\s+&lt;)?/, "<a href=\"javascript:ri('\\1')\">\\1</a>\\2") + "</h2>\n"
  end

  text.sub!(/^\(from/, "\n<br />(from")
  text.gsub!(/^\(from/, "\n<br /><br /><br /><br /><hr>(from")
  text.sub!(/\A= (([A-Z_]\w*::)*[A-Z_]\w*)((#|::|\.).*)$/) do
    # "WRONG 1>#{$1} 2>#{$2} 3>#{$3} 4>#{$4}"
    method    = $3
    namespace = $1.split("::")
    linked    = (0...namespace.size).map do |i|
      "<a href=\"javascript:ri('#{namespace[0..i].join('::')}')\">#{namespace[i]}</a>"
    end
    "<h2>#{linked.join("::")}#{method}</h2>\n"
  end

 
  text.gsub!(/^= (Constants:)([^=]*)(\n\n)/m) do
    head, consts, foot = $1, $2, $3
    consts.gsub!(/:\s*\[not documented\]\s*/, ',').chomp!(',')
    "<h3>" + head + "</h3>" + consts + foot
  end
  
  text.gsub!(/^= (Includes:)(.+?)(\n\n)/m) do
    head, meths, foot = $1, $2, $3
    head + meths.gsub(/([A-Z_]\w*)\(([^)]*)\)/) do |match|
      "<a href=\"javascript:ri('#{$1}')\">#{$1}</a>(" +
      link_methods("#{$1}#", $2) + ")"
    end + foot
  end

  text.gsub!(/^= (Class methods:)(.+?)(\n\n)/m) do
    "<h3>" + $1 + "</h3>" + link_methods("#{term}.", $2) + $3
  end

  text.gsub!(/^= (Instance methods:)(.+?)(\n\n)/m) do
    "<h3>" + $1 + "</h3>" + link_methods("#{term}#", $2) + $3
  end

  text.gsub!(/(?:\n+-+$)?\n+([\w\s]+)[:.]$\n-+\n+/, "\n\n<h2>\\1</h2>\n")
  text.gsub!(/^-----+$/, '<hr>')

  text.chomp + ""
end

def ri(term)
  documentation = `#{e_sh LINKED_RI} '#{term}' 'js' 2>&1` \
                  rescue "<h1>ri Command Error.</h1>"
  if documentation =~ /\ACouldn't open the index/
    TextMate.exit_show_tool_tip(
      "Index needed by #{RI_EXE} not found.\n" +
      "You may need to run:\n\n"               +
      "  fastri-server -b"
    )
  elsif documentation =~ /\ACouldn't initialize DRb and locate the Ring server./
    TextMate.exit_show_tool_tip("Your fastri-server is not running.")
  elsif documentation =~ /Nothing known about /
    TextMate.exit_show_tool_tip(documentation)
  elsif documentation.sub!(/\A>>\s*/, "")
    choices = documentation.split
    choice  = TextMate::UI.menu(choices)
    exit if choice.nil?
    ri(choices[choice])
  else
    [term, documentation]
  end
end

mode = ARGV.shift
if mode.nil? then

  term = STDIN.read.strip

  if term.empty?
    term = TextMate::UI.request_string( :title => "Ruby Documentation Search",
                                        :prompt => "Enter a term to search for:",
                                        :button1 => "search")
  end
  
  TextMate.exit_show_tool_tip("Please select a term to look up.") if term.empty?

  term, documentation = ri(term)

  html_header("Documentation for ‘#{term}’", "RDoc", <<-HTML)
<script type="text/javascript" charset="utf-8">
  function ri (arg, _history) {
    TextMate.isBusy = true;
    var res = TextMate.system("RUBYLIB=#{e_js_sh "#{ENV['TM_SUPPORT_PATH']}/lib"} #{e_js_sh LINKED_RI} 2>&1 '" + arg + "' 'js'", null).outputString;
    document.getElementById("actual_output").innerHTML = res;
    TextMate.isBusy = false;
    if(!_history)
    {
      var history = document.getElementById('search_history');
      var new_option = document.createElement('option');
      new_option.setAttribute('value', arg);
      new_option.appendChild(document.createTextNode(arg));
      history.appendChild(new_option);
      history.value = arg;
    }
  }
</script>
HTML
  puts <<-HTML
<select id="search_history" style="float: right;">
  <option value="#{term}" selected="selected">#{term}</option>
</select>
<script type="text/javascript" charset="utf-8">
  document.getElementById('search_history').addEventListener('change', function(e) {
    ri(document.getElementById('search_history').value, true);
  }, false);
</script>
<div id="actual_output" style="margin-top: 3em">#{documentation}</div>
HTML
  html_footer
  TextMate.exit_show_html
elsif mode == 'js' then
  # TextMate.exit_show_tool_tip("#{e_sh RI_EXE} -T -f rdoc #{e_sh term}")
  documentation = `#{e_sh RI_EXE} -T -f rdoc #{e_sh term}` \
    rescue "<h1>ri Command Error.</h1>"

  if documentation =~ /\A(?:\s*More than one method matched|-+\s+Multiple choices)/
    methods       = documentation.split(/\n[ \t]*\n/).last.
                    strip.split(/(?:,\s*|\n)/).map { |m| m[/\S+/] }.compact
    documentation = ">> #{methods.join(' ')}"
  else
    documentation = htmlize_ri_output(documentation, term)
  end

  puts documentation
end
