#!/usr/bin/env ruby
#2.4.2
require 'colorize'
require 'set'
require 'pry-byebug'

module VP
  class VPTypeError < StandardError; end
  class NoRoomLeftAtTheInn < StandardError; end

  class VisualProgress
    attr_reader :chars, :width
    def initialize(chars: nil)
      #@chars = chars || 
      @line = Line.new
      #Signal.trap('SIGWINCH', resize)
    end

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
      e = line.add_component(content: 'a sentence', fill: true, justify: :right, right_pad: 1, left_pad: 1, style: {background: :blue})
      while true
        sleep(0.2)
        a.update(Time.now)
        b.update(Time.now)
        d.update(spin[spin_idx % 4])
        spin_idx += 1
      end
    end
    private
    attr_reader :line
  end

  class Line < Array
    def initialize(common: nil)
      super()
      @cursor = Cursor.new(self)
      @components = {fills: [], fixed: []}
      @offsets = {}
      @refresh_counter = 0
      rewiden #TODO trap sigwinch and call this
    end

    def refresh(component)
      if @refresh_counter > 64
        @refresh_counter = 0
        reset
      else
        @refresh_counter += 1
        cursor.locate
        cursor.reflow(from: offsets[component], to: offsets[component] + component.length)
      end
    end

    def reset # TODO refactor bc this is ugly af
      # populate the line:
      # 1. clear the line
      # 2. left and right pinned justifieds are placed in the line
      # 3. all fills get an equal slice of the remaining space on the line
      #   # when resizes happen fills extend or retract

      if self.length > 0
        self[0, self.length] = Array.new(self.length) {Character.new(is_bg: true)} # set all to background
      end

      # Fixed width setting
      components[:fixed].select {|a| a.justify == :left}.each do |fixed|
        offset = first_free
        offsets[fixed] = offset
        self[offset, fixed.length] = fixed
      end
      components[:fixed].select {|a| a.justify == :right}.each do |fixed|
        #byebug
        offset = first_free(from: :right) - fixed.length + 1
        offsets[fixed] = offset
        self[offset, fixed.length] = fixed
      end

      # Variable width setting (aka fills)
      if components[:fills].length > 0
        #byebug
        fill_space_per = ((first_free(from: :right) - first_free) / components[:fills].length).floor
      end
      components[:fills].select {|a| a.justify == :left}.each do |fill|
        offset = first_free
        offsets[fill] = offset
        self[offset, fill_space_per] = fill
      end
      components[:fills].select {|a| a.justify == :right}.each do |fill|
        offset = first_free(from: :right) - fill_space_per + 1
        offsets[fill] = offset
        self[offset - fill_space_per, fill_space_per] = fill
      end
      cursor.reflow
    end

    def add_component(content:, style: {}, fill: false, left_pad: 0, right_pad: 0, justify: :left)
      args = {content: content, style: style, fill: fill, left_pad: left_pad, right_pad: right_pad, justify: justify}
      new_component = Component.new(line: self, **args)
      new_component.fill ? components[:fills].push(new_component) : components[:fixed].push(new_component)
      reset
      new_component
    end

    def del_component(component)
      # TODO
    end

    private
    attr_accessor :cursor, :background, :components, :offsets
    def first_free(from: :left)
      idx = nil
      from == :left && idx = self.index {|x| x.is_bg}
      from == :right && idx = self.rindex {|x| x.is_bg}

      idx.nil? && raise(VP::NoRoomLeftAtTheInn, 'The line\'s full')
      idx
    end

    def rewiden
      delta = terminal_width - self.length
      delta.negative? ? shorten(delta.abs) : lengthen(delta)
    end

    def lengthen(delta)
      self.push(*Array.new(delta) {Character.new(is_bg: true)})
      # ^ we do it this janky way because you can't += on self (no self reassign)
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

  class Component < Array
    attr_accessor :style, :left_pad, :right_pad, :justify
    attr_reader :fill

    def initialize(line:, content:, style: {}, fill: false, left_pad: 0, right_pad: 0, justify: :left)
      super()
      @line = line
      @style = style
      @left_pad = left_pad
      @right_pad = right_pad
      @fill = fill
      @justify = justify
      update(content)
    end

    def update_style(style)
      self.map{|x| x.update_style(style)}
    end

    def update(str)
      hard = false
      if self.length == 0
        hard = true
      end
      str
        .to_s
        .chars
        .unshift(*Array.new(left_pad) {' '})
        .push(*Array.new(right_pad) {' '})
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
    attr_reader :line
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
      (line.length * 2).times {left}
    end

    def reflow(from: 0, to: nil)
      to ||= upper_bound
      line[from, to].nil? && byebug
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
