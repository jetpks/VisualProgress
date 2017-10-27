#!/usr/bin/env ruby
# 2.4.2
require './lib/visual-progress.rb'
asdf = VP::VisualProgress.new

default_style = {background: :blue, color: :white, mode: :bold}
asdf.components.add(style: default_style, pad: {right: 2, left: 0}) {Time.now.to_s}
#asdf.components.add(
while true
  sleep rand(1..7)
  asdf.writer.puts("testing testing, one two three")
  sleep rand(1..7)
  asdf.writer.puts("oawefmoawiemfoaijo")
end
sleep 1000
puts


=begin
    def timestamp
      spin = %w{\\ | / -}
      spin_idx = 0
      a = line.add_component(content: Time.now, left_pad: 4, right_pad: 4)
      #  byebug
      b = line.add_component(content: Time.now, justify: :right, left_pad: 4, right_pad: 4)
      #  byebug
      c = line.add_component(content: 'hello', style: {background: :blue, color: :red, mode: :bold})
      #  byebug
      d = line.add_component(content: spin[0], left_pad: 2, justify: :right, right_pad: 2, style: {background: :yellow, color: :black, mode: :bold})
      #  byebug
      e = line.add_component(content: 'a sentence', justify: :right, right_pad: 1, left_pad: 1, style: {color: :white, background: :blue, mode: :bold})
      4096.times do |x|
        deferred_winch?
        sleep(0.2)
        a.update(Time.now)
        b.update(Time.now)
        d.update(spin[spin_idx % 4])
        spin_idx += 1
        if x % 48 == 0
          line.print_over(<<-HERE
                          Now, we're going to try a heredoc with a big ass long line that would represent some kind of novel
                          someone wants to log. Once upon a time in a mysterious world of Exceptiontopia there was a mad
                          wizard king named Fronald GlobalInterpreterLock. He was a bastard.

                          Our old wise hero named C, of whom we got to know and love in ACT I faced the terrible task of
                          venturing to the land of RAM to extract The One True Root Key that would allow Fronald GIL to rule
                          the land of Exceptiontopia for ever and ever. It was that, or be put to death by all the kings men.

                          <adventure where the hero nearly dies, and grows stronger and more HUMBLE. (sit down)>

                          Hero goes back to Exceptiontopia with The One True Root Key, places it in front of Fronald GIL, but
                          chooses to destroy it, killing Fronald in the process. C became king, and the land of Exceptiontopia
                          lived happily for the reest of time.
                          HERE
          )
        end
      end
    end
=end
