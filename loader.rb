class Loader
  def initialize(command_dir)
    @command_dir = command_dir
    @commands = {}
  end

  def load_commands
    Dir.glob(File.join(@command_dir, '*.rb')).each do |file|
      command_name = File.basename(file, '.rb')
      load_command(command_name)
    end
  end

  def command(name) = @commands[name]
  
  def load_command(command_name)
    command_code = File.read(File.join(@command_dir, command_name+".rb"))

    begin
      command_class = Class.new
      command_class.class_eval(command_code)
      
      if command_class.instance_methods.include?(:call)
        @commands[command_name] = command_class.new
      else
        puts "Error: #{command_name} does not implement 'call' method"
      end
    rescue SyntaxError, LoadError, StandardError => e
      puts "Error loading #{command_name}: #{e.message}"
    end
  end

  def exists?(name) = @commands.key?(name)
  
  def call(name, *args)
    if @commands.key?(name)
      @commands[name].call(*args)
    else
      puts "Unknown command: #{command_name}"
    end
  end
end
