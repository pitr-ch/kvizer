#!/usr/bin/env ruby

lib_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$: << lib_path unless $:.include? lib_path

require 'virtual'
require 'virtual/runner'

Virtual::Runner.new.parse.run
