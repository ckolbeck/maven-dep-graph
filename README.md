Maven Dependency Grapher
========================

**WIP**

Only display-svg-in-browser is really tested.

This should be split into multiple files but I'm lazy.

I'm bad at dynamic languages and this is the first thing longer
than 5 lines I've written in ruby. It's pretty bad.

Requirements
------------

* Ruby 2.x
* Maven 3.x
* GraphViz 2.x
* Unflatten (Usually packaged with GraphViz)

Invocation
----------

Expects to be run at the root of a maven project.

    ./mdeps.rb [OPTIONS] [PATTERNS]

Options
-------

    -b COMMAND
    --browser COMMAND
When viewing result directly, what viewing program to invoke. Must accept a single
filename as its first argument to open. Default: `google-chrome` 

    -o OUTPUT
    --output-file OUTPUT
Where to write the generated graph. use `'-'` to write to stdout.

    -f <svg|pdf|png>
    --output-format
What format to generate. Currently `svg`, `pdf`, and `png` are supported. Default: `svg`

    --scopes SCOPES
**Currently Broken** Dependency scopes to include, comma separated. See maven docs for
full list. Default: `compile,runtime`

    -v
    --[no-]verbose
**Currently Broken** due to a maven dependency plugin bug.
Controls whether mvn dependency:tree is invoked with the `verbose` flag. Default: false.

    -d
    --[no-]debug
Produce debugging output. Default: false

Output
------

The generated graph includes all paths from project parent/modules to dependencies matching provided patterns.
Project roots are marked with a black fill. Nodes matching any of the search patterns are marked with gold.

Patterns
--------

Currently only matching on group and artifact are supported. Matching uses implicitly anchored globbing.
Dependencies are considered matching if they match any of the provided patterns.

Match exact dep:

    ./mdeps.rb 'dep-group:dep-artifact'

Match everything with either group or artifact of search-str:

    ./mdeps.rb 'search-str'

Match anything with search-str in either the group or artifact:

    ./mdeps.rb '*search-str*'

Match anything with search-str in the artifact:

    ./mdeps.rb '*:*search-str*'

Specifying no patterns will generate a graph of all dependencies.