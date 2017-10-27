#!/usr/bin/env ruby
#2.4.2

require 'colorize'
require 'set'
require 'pry-byebug'

module VP
  class VPTypeError < StandardError; end
  class NoRoomLeftAtTheInn < StandardError; end

  class VisualProgress
    attr_accessor :sleep_time
    attr_reader :chars, :width, :components, :writer

    def initialize(sleep_time: 0.2)
      @sleep_time = sleep_time
      @line = Line.new
      @winch = Winch.new {line.refresh}
      @stdout_queue = Queue.new
      @components = Components.new(line)
      line.components = @components.members

      read, write = IO.pipe
      @writer = write
      Thread.new(read) {|read| read_thread(read)}.abort_on_exception = true
      Thread.new {write_thread}.abort_on_exception = true
    end

    def read_thread(pipe)
      while true
        stdout_queue << pipe.gets
      end
    end

    def write_thread
      while true
        winch.deferred?
        dequeue_all
        components.update
        delay
      end
    end

    def dequeue_all
      stdout_queue.length.times {
        line.print_over(stdout_queue.pop(non_block = true))
      }
    rescue ThreadError # where we pop an empty queue with non_block = true
    end

    def delay
      sleep(sleep_time)
    end

    private
    attr_reader :line, :stdout_queue, :winch
  end

  class Components
    attr_reader :members
    def initialize(line)
      @line = line
      @members = []
    end

    def add(style: {}, pad: {left: 0, right: 0}, justify: :left, &callback)
      members << Component.new(line, callback, style, pad, justify)
      line.reset
    end

    def update
      members.each {|x| x.update}
    end

    private
    attr_reader :line

    class Component < Array
      attr_accessor :style, :pad, :justify
      DEFAULT_PAD = {left: 0, right: 0}

      def initialize(line, callback, style, pad, justify)
        super()
        @line = line
        @style = style
        @pad = DEFAULT_PAD.merge(pad)
        @justify = justify
        @callback = callback
        update
      end

      def update_style(style)
        self.map{|x| x.update_style(style)}
      end

      def update
        hard = !(self.length > 0)
        #byebug

        callback.call
          .to_s
          .chars
          .unshift(*Array.new(pad[:left]) {' '})
          .push(*Array.new(pad[:right]) {' '})
          .each_with_index do |char, i|

          if self[i].nil?
            self[i] = Character.new(content: char, style: style)
          else
            self[i].content = char if (self[i].is_bg || self[i].content != char)
          end
        end

        hard ? line.reset : line.refresh(self)
      end

      private
      attr_reader :line, :callback
    end # Component
  end # Components

  class Winch
    attr_reader :deferred, :last
    def initialize(&callback)
      @deferred = false
      @last = now
      @callback = callback
      Signal.trap('SIGWINCH', self.method(:handle))
    end

    def deferred?
      if deferred && last < now - 2
        handle
      end
    end

    def handle(*args)
      unless suppress_burst
        @deferred = false
        @last = now
        callback.call
      end
    end

    def suppress_burst
      @deferred = last >= now - 2
    end

    private
    attr_reader :callback

    def now
      Time.now.to_i
    end
  end

  class Line < Array
    attr_accessor :components

    def initialize
      super()
      @cursor = Cursor.new(self)
      @components = []
      @offsets = {}
      @refresh_counter = 0
      rewiden
    end

    def print_over(*args)
      clear_line
      cursor.locate
      puts "\n" + args.join(' ')
      reset
    end

    def refresh(component)
      to = offsets[component].nil? ? nil : offsets[component] + component.length
      @refresh_counter > 64 ? reset : cursor.reflow(from: offsets[component], to: to)
      @refresh_counter += 1
    end

    def clear_line
      self.length > 0 && self[0, self.length] = Array.new(self.length) {Character.new(is_bg: true)} # set all to background
    end

    def reset
      @refresh_counter = 0
      clear_line
      cursor.locate

      components.each do |c|
        offset = c.justify == :left ? first_free : first_free(from: :right) - c.length + 1
        offsets[c] = offset
        self[offset, c.length] = c
      end

      cursor.reflow
    end

    def rewiden(*args)
      delta = terminal_width - self.length
      delta.negative? ? shorten(delta.abs) : lengthen(delta)
    end

    private
    attr_accessor :cursor, :background, :offsets
    def first_free(from: :left)
      idx = nil
      from == :left && idx = self.index {|x| x.is_bg}
      from == :right && idx = self.rindex {|x| x.is_bg}

      idx.nil? && raise(VP::NoRoomLeftAtTheInn, 'The line\'s full')
      idx
    end

    def lengthen(delta)
      self.push(*Array.new(delta) {Character.new(is_bg: true)})
      reset
    end

    def shorten(delta)
      self.pop(delta)
      reset
    end

    def terminal_width
      %x{tput cols}.chomp.to_i
    end
  end

  class Cursor
    attr_reader :position
    def initialize(line)
      if ! line.is_a? VP::Line
        raise VP::VPTypeError, 'cursor MUST have a VP::Line to work with'
      end
      @line = line
      @position = 0
    end

    def locate
      1024.times {down; left}
    end

    def reflow(from: nil, to: nil)
      to ||= upper_bound
      from ||= 0
      line[from, to].each {|c| c.drawn = false}
      [to, from]
        .sort {|a,b| ((position - a).abs < (position - b).abs) ? -1 : 1}
        .each {|target| to(target)}
    end

    def draw
      return false if line[position].nil? || line[position].drawn
      draw!
    end

    def to(target)
      draw && left # take care of those pesky move-to-current-position calls
      distance = target - position
      distance.negative? ? left(distance) : right(distance)
    end

    def left(qty = 1)
      qty.abs.times {
        print "\e[D"
        @position = position <= 0 ? 0 : position - 1
        draw && left
      }
    end

    def right(qty = 1)
      qty.abs.times {
        if ! draw
          print("\e[C")
          @position = position >= upper_bound ? upper_bound : position + 1
        end
      }
    end

    def down(qty = 1)
      print("\e[#{qty}B")
    end

    def up(qty = 1)
      print("\e[#{qty}A")
    end

    def draw!
      print line[position].format
      line[position].drawn = true
      @position = position + 1
      true
    end

    private
    attr_reader :line
    def off_the_end_check # occurs after writing the last character in the line
      to(position - 1) if position >= upper_bound
    end

    def upper_bound
      line.length - 1
    end
  end

  class Character
    attr_accessor :drawn
    attr_reader :content, :style, :is_bg
    DEFAULT_STYLE = {color: :default, background: :default, mode: :default}

    def initialize(content: ' ', style: {}, is_bg: false)
      @style = DEFAULT_STYLE.merge(style)
      @drawn = false
      @content = content
      @is_bg = is_bg
    end

    def format
      content.colorize(**style)
    end

    def style=(new_style)
      @style = style.merge(new_style)
    end

    def content=(new_char)
      @content = new_char
      @drawn = false
    end
  end
end
