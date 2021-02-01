# Processing a compressed json stream

Recently I had a technical problem to solve for a dojo4 client. They receive a realtime stream of newline delimited json events compressed with zlib from a data provider over a raw tcp socket.  

The datastream protocol is pretty simple:

1. Open up a tcp connect to a desginated tcp `host:port`.
2. Recieve a stream of zlib compressed newline delimited json events forever.

There is no protocol authentication, the app I'm working on is assigned a specific `host:port` by the data provider to connect to, and I have told the provider what IP address the application is coming from. That's it. 

Given all of that, the objective is to write a client that:
- connects to the socket
- continutally reads data from the socket
- decompresses that data to a stream of newline delimited JSON
- parses that JSON
- hands that parsed object off to the next stage of the pipeline

### Connecting and Reading
This is the intiial script to test out connecting and receiving data to make sure that works. It connects to the given tcp host and port, and reads 1 megabyte of data from the stream. The full scripts are available via the gist links, I'll just be showing the relavent parts line in this post.

[connecting-client gist](https://gist.github.com/copiousfreetime/e6ea5c901270706271c763fd2fbd355e#file-01_connecting-client-rb)

```ruby
# ...
# Create the socket and make it non-blocking since this application is doing other things
# too
logger.info "Connecting to datasource"
socket = ::Socket.tcp(host, port)
socket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK) # make it non-blocking
logger.info "Socket created #{socket}"

read_buffer = String.new # A resuable string for use by readpartial
bufsize     = 64*1024    # read up to this amount of data from socket
stop_after  = 1024*1024  # 1 megabyte of data
total_bytes = 0
read_count  = 0

logger.info "Connecting to datasource"
logger.info "Reading..."
loop do
  bytes = socket.readpartial(bufsize, read_buffer)
  total_bytes += bytes.bytesize
  read_count += 1
  break if total_bytes > stop_after
end
logger.info "Stopped after #{total_bytes} read in #{read_count} reads"

```
And when this is run:

```
$ ./01_connecting-client.rb $HOST $PORT
2021-01-30T21:10:56Z 27940  INFO : Socket created
2021-01-30T21:10:56Z 27940  INFO : Reading...
2021-01-30T21:10:56Z 27940  INFO : Stopped after 1051250 bytes read in 641 reads
```

Excellent, the connection works and bytes are received.

## Reading zlib compressed data

Now the next bit is to make sure we can decompress the zlib stream. Some might think that this would just be passing it off to `gunzip`. That would be incorrect. This is an infinite stream of bytes from a socket. And although the gzip file format is compressed with the DEFLATE compression algorithm implemented by zlib, the gzip file format has a header and a footer. Headers and footers are not possible in a continuous stream, which has no beginning nor end.

Luckily handling DEFLATE is built into the ruby standard library via `zlib`. What we need to do is for each of those buffers read from the socket to be decompressed. If we update the code around the loop we get the following:

[decompressing-client gist](https://gist.github.com/copiousfreetime/e6ea5c901270706271c763fd2fbd355e#file-02_decompressing-client-rb)
```ruby
# .. see the full gist for the 
#
compressed_buffer  = String.new # A resuable string for use by readpartial for compressed bytes
inflater           = ::Zlib::Inflate.new(::Zlib::MAX_WBITS + 32)
uncompressed_bytes = 0

logger.info "Reading..."
logger.info "Writing to #{output_to}"

output = output_to == "-" ? $stdout : File.open(output_to, "w+")

loop do
  socket.readpartial(bufsize, compressed_buffer)
  total_bytes += compressed_buffer.bytesize
  read_count += 1
  uncompressed_buffer = inflater.inflate(compressed_buffer)
  uncompressed_bytes += uncompressed_buffer.bytesize
  output.write(uncompressed_buffer)
  break if total_bytes > stop_after
end
output.close

logger.info "Read #{read_count} times from data source"
logger.info "Received #{total_bytes} of compressed data"
logger.info "Resulting in #{uncompressed_bytes} of decompressed data"
```

Run the script and then check the output to see if this looks like reasonable JSON data.  One of the fields in the json is `t` which is a timestamp. Using `jq` to go through this line oriented json and extract out the `t` field it looks the data is received correctly.

After running it and testing  - it looks good - except for the last line. This is to be expected as the bytes we're reading from the data are compressed bytes and the code decompresses it as blocks. The data is not line oriented yet.

```
$ ./decompressing_client.rb  $HOST $PORT output.json
2021-01-30T21:45:45Z 28817  INFO : Socket created
2021-01-30T21:45:45Z 28817  INFO : Reading...
2021-01-30T21:45:45Z 28817  INFO : Writing to output.json
2021-01-30T21:45:45Z 28817  INFO : Read 295 times from data source
2021-01-30T21:45:45Z 28817  INFO : Received 1049591 of compressed data
2021-01-30T21:45:45Z 28817  INFO : Resulting in 3858614 of decompressed data

$ wc output.json
   2805   51512 3858614 output.json
$ jq .t < output.json  > /dev/null
parse error: Unfinished string at EOF at line 2806, column 1431
```

## Converting blocks of text to newlines

Normally when reading from an IO object in ruby, to parse the input into newlines, I would just use `IO#readline` or `IO#gets`. In this case, the decompressed bytes are not in an `IO` object, they are a block of bytes, and there may or may-not be a newline in it depending on how much was read and decompressed from the socket.

Originally I thought about writing something similar to a Java BufferedReader to convert the uncompressed bytestream into newlines. And then realized, It already exists in ruby -  [`IO.pipe`](https://rubyapi.org/2.7/o/io#method-c-pipe). 

> `IO.pipe` creates a pair of pipe endpoints (connected to each other) and returns them as a two-element array of [`IO`](https://rubyapi.org/2.7/o/io) objects: `[` _read\_io_, _write\_io_ `]`.

If the decompressed bytes are written to one end of the pipe, then lines may be read from the other end of the pipe, since it is an `IO` object and has both the `gets` and `readline` methods.  In short something like this:

```ruby
read_io, write_io = IO.pipe

write_io.write(bunch_of_bytes)

while line = read_io.gets do
  # do something with line
end
```

## Bringing it all together

This changes the architecture of the program and moves it into a concurrent direction. We need
-  one thread to read the datastream from the socket, decompress it and send it down the pipe
-  another thread to read from the pipe as newlines and parse the json
- a third to process the parsed json.

[json-parsing-client gist](https://gist.github.com/copiousfreetime/e6ea5c901270706271c763fd2fbd355e#file-03_json-parsing-client-rb)

Extract out the reading from the socket and decompressing  to a class that will be put in its own thread.
```ruby
#
# class to read data from an input IO, decompress the data, and write it to an
# output IO. it'll collect stats during the process
#
class Decompressor
  attr_reader :input
  attr_reader :output
  attr_reader :top_after
  attr_reader :buffer_size
  attr_reader :compressed_bytes
  attr_reader :uncompressed_bytes
  attr_reader :read_count

  def initialize(input:, output:, stop_after: Float::INFINITY)
    @input = input
    @output = output
    @stop_after = stop_after
    @buffer_size =  64*1024 # How much maximum data to read from the socket at a go
    @compressed_bytes = 0
    @uncompressed_bytes = 0
    @read_count = 0
  end

  def call
    compressed_buffer = String.new
    inflater  = ::Zlib::Inflate.new(::Zlib::MAX_WBITS + 32)

    loop do
      input.readpartial(@buffer_size, compressed_buffer)
      @compressed_bytes += compressed_buffer.bytesize
      @read_count += 1
      uncompressed_buffer = inflater.inflate(compressed_buffer)
      @uncompressed_bytes += uncompressed_buffer.bytesize
      output.write(uncompressed_buffer)
      break if @compressed_bytes > @stop_after
    end
    output.close
  end
end
```

Put the reading of the decompressed data into lines and parsing into json into its own class

```ruby
#
# class to read newlines from an input and write the output parsed object something
# else that responds to `<<`
#
class Parser
  attr_reader :item_count
  attr_reader :input_bytes

  def initialize(input:, output:)
    @item_count = 0
    @input_bytes = 0
    @stop = false
    @input = input
    @output = output
  end

  def stop
    @stop = true
  end

  def call
    loop do
      break if @stop
      line = @input.readline
      @input_bytes += line.bytesize
      event = JSON.parse(line)
      @output << event
      @item_count += 1
    end
  end
end
```

And tie all of this up using `IO.pipe` and a `Queue` so the parser can shovel off the events to something else.

```ruby
# Create the socket and make it non-blocking since this application is doing other things
# too
socket = ::Socket.tcp(host, port)
socket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK) # make it non-blocking

# Create a pipe to buffer the uncompressed data from the socket so that the text may be
# parsed into newlines.
#
read_io, write_io = IO.pipe
write_io.set_encoding("BINARY") # to handle multibyte-character splitting

events       = Queue.new
decompressor = Decompressor.new(input: socket, output: write_io, stop_after: stop_after)
parser       = Parser.new(input: read_io, output: events)

# spawn threads for each of the objects
decompressor_thread = Thread.new { decompressor.call }
parser_thread = Thread.new { parser.call }

# spawn a thread to consume all the events from the parser and throw them away
consumed_count = 0
consumer_thread = Thread.new {
  loop do
    e = events.deq
    consumed_count += 1 unless e.nil?
    break if events.closed? && events.empty?
  end
}
```

You may be wondering about the line `write_io.set_encoding("BINARY")`. This particular item took a while to figure out. The data that is coming out of the decompressor are raw bytes. Those bytes need to be interpreted as UTF-8 characters since JSON requires UTF-8. There are multi-byte UTF-8 characters and it is pretty much guaranteed that at some point a multibyte UTF-8 character is going to be split across decompression chunks.

By default the pipe ends up with a default encoding of UTF-8 on both input and output. When the decompressor writes uncompressed bytes to the pipe, if there is a partial multibyte UTF-8 character in that write operation, then ruby will raise an exception since the byte sequence is not a valid UTF-8 sequence.

With the write side of the pipe having a `BINARY` encoding set, the pipe is now effectively a buffer that converts unencoding bytes to a line oriented UTF-8 characters.

Runing this new script results in:
```
$ ./json_parsing_client.rb  $HOST $PORT
2021-02-01T20:19:24Z 10004  INFO : Decompressor: read 245 times
2021-02-01T20:19:24Z 10004  INFO : Decompressor: received 1041114 bytes
2021-02-01T20:19:24Z 10004  INFO : Decompressor: forwarded on 3844323 bytes
2021-02-01T20:19:24Z 10004  INFO : Parser      : received 3814991
2021-02-01T20:19:24Z 10004  INFO : Parser      : forwarded on 2581 events
2021-02-01T20:19:24Z 10004  INFO : Consumer    : threw away 2581 events
```


