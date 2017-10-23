#!/usr/bin/env ruby
#2.4.2
require 'colorize'
require 'set'
require 'pry'

module VP
  class VisualProgress
    attr_reader :chars, :width
    def initialize(chars: nil)
      @chars = chars || %w{\\ | / -}
      @line = Line.new
      #Signal.trap('SIGWINCH', resize)
    end

    def timestamp
      while true
        sleep(0.2)
        write(Time.now)
      end
    end

    def write(content, offset = 0)
      changes = []

      content.to_s.chars.each_with_index do |c, i|
        candidate = Character.new(content: c)
        if line.line[i + offset] != candidate
          line.line[i + offset] = candidate
          changes << i + offset
        end
      end

      if changes.length > 0
        line.reflow(from: changes[0], to: changes[-1])
      end
    end

    def spin
      first = true
      while true
        bg = String.colors.sample
        chars.each do |ch|
          sleep 0.2
          if first
            first = false
          else
            print "\b"
          end
          print ch.colorize(color: String.colors.sample, background: bg)
        end
      end
    end
    private
    attr_reader :line
  end

  class Line
    attr_reader :line
    def initialize(common: nil)
      @line = []
      @cursor = 0

      setup_line(common)
    end

    def reflow(from: 0, to: nil) # args default to upper and lower bounds
      # variable prep
      to.nil? && to = line.length - 1

      # inverted range (we handle right to left scanning automatically)
      if from > to
        tmp = from
        from = to
        to = tmp
      end

      # shortcut cases -- entire range can be covered in a single movement
      if to == from && from == cursor
        sync_under
        return
      end

      if cursor <= from
        move_cursor_to(to)
        return
      end

      if cursor >= to
        move_cursor_to(from)
        return
      end

      # cursor is in the middle of the range, so some places will be double
      # checked. minimize double checking by moving to the closest bound
      if (cursor - from).abs < (cursor - to).abs
        # cursor is closer to start of range
        move_cursor_to(from)
        move_cursor_to(to)
      else
        # cursor is closer to end of range
        move_cursor_to(to)
        move_cursor_to(from)
      end
    end

    def write(content:, offset: 0)
      content.chars.each_with_index do |char, idx|
        line[offset + idx].content = char
      end
      reflow
    end

    private
    attr_accessor :cursor
    def setup_line(common)
      terminal_width.times {line << Character.new(from: common)}
      reflow
    end

    def draw(position)
      move_cursor_to(position)
      line[position].draw
      @cursor += 1
      off_the_end_check
    end

    def off_the_end_check
      cursor_left if line[cursor].nil?
    end

    def move_cursor_to(desired_location)
      distance = desired_location - cursor
      return if distance == 0

      if distance.negative?
        distance.abs.times {cursor_left}
      else
        distance.times {cursor_right}
      end
    end

    def sync_under
      if ! line[cursor].drawn
        draw(cursor)
        cursor_left
      end
    end

    def cursor_left
      print "\e[D"
      @cursor = cursor <= 0 ? 0 : cursor - 1

      sync_under
    end

    def cursor_right
      print "\e[C"
      @cursor = cursor >= line.length - 1 ? line.length - 1 : cursor + 1

      sync_under
    end

    def terminal_width
      %x{tput cols}.chomp.to_i
    end
  end

  class Character
    attr_reader :content, :fg_color, :bg_color, :style, :drawn
    def initialize(from: nil, content: ' ', fg_color: :default, bg_color: :default, style: :default)
      if ! from.nil?
        @content = from.content
        @fg_color = from.fg_color
        @bg_color = from.bg_color
        @style = from.style
      else
        @content = content
        @fg_color = fg_color
        @bg_color = bg_color
        @style = style
      end
      @drawn = false
    end

    def draw
      print format
      @drawn = true
    end

    def undraw!
      @drawn = false
    end

    def format
      content.colorize(color: fg_color, background: bg_color, style: style)
    end

    def blank?
      content == ' '
    end

    def blank!
      content = ' '
      @drawn = false
    end

    # operators
    def ==(char)
      @content == char.content &&
        @fg_color == char.fg_color &&
        @bg_color == char.bg_color &&
        @style == char.style
    end

    # setters
    def set(content: nil, fg_color: nil, bg_color: nil, style: nil)
      @content = content if content
      @fg_color = fg_color if fg_color
      @bg_color = bg_color if bg_color
      @style = style if style
      @drawn = false
    end

    def content=(content)
      @drawn = false
      @content = content
    end

    def fg_color=(color)
      @drawn = false
      @fg_color = color
    end

    def bg_color=(color)
      @drawn = false
      @bg_color = color
    end

    def style=(style)
      @drawn = false
      @style = style
    end
  end
end
