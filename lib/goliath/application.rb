require 'goliath/goliath'
require 'goliath/runner'
require 'goliath/rack'

module Goliath
  # The main execution class for Goliath. This will execute in the at_exit
  # handler to run the server.
  #
  # @private
  module Application
    # Most of this stuff is straight out of sinatra.

    # Set of caller regex's to be skipped when looking for our API file
    CALLERS_TO_IGNORE = [ # :nodoc:
      /\/goliath(\/application)?\.rb$/, # all goliath code
      /\/goliath(\/(rack|validation|plugins)\/)/, # all goliath code
      /rubygems\/custom_require\.rb$/,    # rubygems require hacks
      /bundler(\/runtime)?\.rb/,          # bundler require hacks
      /<internal:/                        # internal in ruby >= 1.9.2
    ]

    # @todo add rubinius (and hopefully other VM impls) ignore patterns ...
    CALLERS_TO_IGNORE.concat(RUBY_IGNORE_CALLERS) if defined?(RUBY_IGNORE_CALLERS)

    module_function

    # Control whether or not the application will be run using an at_exit block.
    class << self
      attr_accessor :run_app_on_exit
      alias_method :run_app_on_exit?, :run_app_on_exit
    end

    # By default, we do run the application using the at_exit block.
    self.run_app_on_exit = true

    # Like Kernel#caller but excluding certain magic entries and without
    # line / method information; the resulting array contains filenames only.
    def caller_files
      caller_locations.map { |file, line| file }
    end

    # Like caller_files, but containing Arrays rather than strings with the
    # first element being the file, and the second being the line.
    def caller_locations
      caller(1).
        map    { |line| line.split(/:(?=\d|in )/)[0,2] }.
        reject { |file, line| CALLERS_TO_IGNORE.any? { |pattern| file =~ pattern } }
    end

    # Find the app_file that was used to execute the application
    #
    # @return [String] The app file
    def app_file
      c = caller_files.first
      c = $0 if !c || c.empty?
      c
    end

    # Returns the userland class which inherits the Goliath API
    #
    # @return [String] The app class
    def app_class
      @app_class
    end

    # Sets the userland class that should use the Goliath API
    #
    # @param app_class [String|Symbol|Constant] The new app class
    # @return [String] app_class The new app class
    def app_class=(app_class)
      @app_class = app_class.to_s
    end

    # Retrive the base directory for the API before we've changed directories
    #
    # @note Note sure of a better way to handle this. Goliath will do a chdir
    #       when the runner is executed. If you need the +root_path+ before
    #       the runner is executing (like, in a use statement) you need this method.
    #
    # @param args [Array] Any arguments to append to the path
    # @return [String] path for the given arguments
    def app_path(*args)
      @app_path ||= File.expand_path(File.dirname(app_file))
      File.join(@app_path, *args)
    end

    # Retrieve the base directory for the API
    #
    # @param args [Array] Any arguments to append to the path
    # @return [String] path for the given arguments
    def root_path(*args)
      return app_path(args) if Goliath.env?(:test)

      @root_path ||= File.expand_path("./")
      File.join(@root_path, *args)
    end

    # Execute the application
    #
    # @return [Nil]
    def run!
      unless @app_class
        file = File.basename(app_file, '.rb')
        @app_class = camel_case(file)
      end

      begin
        klass = Kernel
        @app_class.split('::').each { |con| klass = klass.const_get(con) }
      rescue NameError
        raise NameError, "Class #{@app_class} not found."
      end

      api = klass.new

      runner = Goliath::Runner.new(ARGV, api)
      runner.app = Goliath::Rack::Builder.build(klass, api)

      runner.load_plugins(klass.plugins)
      runner.run
    end

    private

    # Convert a string to camel case
    #
    # @param str [String] The string to convert
    # @return [String] The camel cased string
    def camel_case(str)
      return str if str !~ /_/ && str =~ /[A-Z]+.*/

      str.split('_').map { |e| e.capitalize }.join
    end
  end

  at_exit do
    # Only run the application if ...
    #  - we want it to run
    #  - there has been no exception raised
    #  - the file that has been run, is the goliath application file
    if Goliath::Application.run_app_on_exit? && $!.nil? && $0 == Goliath::Application.app_file
      Application.run!
    end
  end
end
