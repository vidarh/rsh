
require 'openai'
require 'openai'

OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_API_KEY"]
end

attr_reader :messages, :chat, :reply

def initialize
  @client = OpenAI::Client.new

  @messages = []
  @chat = []
  @reply = ""
end

def clear
  @messages = []
  @chat = []
  @reply = ""
end
  
def call(*args)
  if args[0] == "--clear"
    clear
    puts
    return
  end

  if args[0] == "--messages"
    return @messages
  end

  if args[0] == "--chat"
    return @chat
  end
    

  @chat << { role: "user", content: args.join(" ") }

  @reply = ""
  
  stream_proc = proc do |chunk, _bytesize|
    @messages << chunk
    ob = chunk.dig("choices",0, "delta")
    r = (ob&.dig("content")).to_s
    print r
    @reply += r
    if !ob
      puts
      @chat << { role: "assistant", content: @reply }
    end
  end
  
  @client.chat(
    parameters: {
      model: "gpt-4o",
      stream: stream_proc,
      stream_options: { include_usage: true },
      messages: @chat
    })

  @messages[-1].dig("usage")
end
