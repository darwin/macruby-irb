#
#  console.rb
#
#  Copyright (c) 2006 Tim Burks, Neon Design Technology, Inc.  
#  Released under the same license as Console.
#  Find more information about this file online at http://www.rubycocoa.com/mastering-cocoa-with-ruby
#
#  23.09.2008 - ported to MacRuby 0.3 by Antonin Hildebrand
#

require 'irb'

class ConsoleWindowController
  attr_accessor :window, :textview, :console
  def initWithFrame(frame)
    init
    styleMask = NSTitledWindowMask + NSClosableWindowMask + NSMiniaturizableWindowMask + NSResizableWindowMask
    @window = NSWindow.alloc.initWithContentRect(frame, 
      styleMask: styleMask, 
      backing: NSBackingStoreBuffered, 
      defer: false
    )
    @textview = NSTextView.alloc.initWithFrame(frame)
    @console = RubyConsole.alloc.initWithTextView(@textview)
    with @window do |w|
      w.setContentView(scrollableView(@textview))
      w.setTitle "MacRuby Console"
      w.setDelegate self
      w.center
      w.makeKeyAndOrderFront(self)
    end
    self
  end

  def run
    @console.performSelector("run:", withObject: self, afterDelay: 0)
  end

  def show(sender)
    console = ConsoleWindowController.alloc.initWithFrame([50,50,600,300])
    console.run
  end
end

def with(x)
  yield x if block_given?; x
end if not defined? with

def scrollableView(content)
  scrollview = NSScrollView.alloc.initWithFrame(content.frame)
  clipview = NSClipView.alloc.initWithFrame(scrollview.frame)
  scrollview.setContentView(clipview)
  scrollview.setDocumentView(content)
  clipview.setDocumentView(content)
  content.setFrame(clipview.frame)
  scrollview.setHasVerticalScroller(1)
  scrollview.setHasHorizontalScroller(1)
  scrollview.setAutohidesScrollers(1)
  resizingMask = NSViewWidthSizable + NSViewHeightSizable
  content.setAutoresizingMask(resizingMask)
  clipview.setAutoresizingMask(resizingMask)
  scrollview.setAutoresizingMask(resizingMask)
  scrollview
end

class ConsoleInputMethod < IRB::StdioInputMethod
  def initialize(console)
    super() # superclass method has no arguments
    @console = console
    @history_index = 1
    @continued_from_line = nil
  end

  def gets
    m = @prompt.match(/(\d+)[>*]/)
    level = m ? m[1].to_i : 0
    if level > 0
      @continued_from_line ||= @line_no
    elsif @continued_from_line
      mergeLastNLines(@line_no - @continued_from_line + 1)
      @continued_from_line = nil
    end
    @console.write @prompt+"  "*level
    string = @console.readLine
    @line_no += 1
    @history_index = @line_no + 1
    @line[@line_no] = string
    string
  end

  def mergeLastNLines(i)
    return unless i > 1
    range = -i..-1
    @line[range] = @line[range].map {|l| l.chomp}.join("\n")
    @line_no -= (i-1)
    @history_index -= (i-1)
  end

  def prevCmd
    return "" if @line_no == 0
    @history_index -= 1 unless @history_index <= 1
    @line[@history_index]
  end

  def nextCmd
    return "" if (@line_no == 0) or (@history_index >= @line_no)
    @history_index += 1
    @line[@history_index]
  end
end

# this is an output handler for IRB 
# and a delegate and controller for an NSTextView
class RubyConsole
  attr_accessor :textview, :inputMethod

  def initWithTextView(textview)
    init
    @textview = textview
    @textview.setDelegate(self)
    @textview.setRichText(false)
    @textview.setContinuousSpellCheckingEnabled(false)
    @inputMethod = ConsoleInputMethod.new(self)
    @context = Kernel::binding
    @startOfInput = 0
    self
  end

  def run(sender = nil)
    @textview.window.makeKeyAndOrderFront(self)
    IRB.startInConsole(self)
    NSApplication.sharedApplication.terminate(self)
  end

  def write(object)
    string = object.to_s
    @textview.textStorage.insertAttributedString(NSAttributedString.alloc.initWithString(string), atIndex: @startOfInput)
    @startOfInput += string.length
    @textview.scrollRangeToVisible([lengthOfTextView, 0])
    handleEvents if NSApplication.sharedApplication.isRunning
  end

  def moveAndScrollToIndex(index)
    range = NSRange.new(index, 0)
    @textview.scrollRangeToVisible(range)
    @textview.setSelectedRange(range)
  end

  def lengthOfTextView
    @textview.textStorage.mutableString.length
  end

  def currentLine
    text = @textview.textStorage.mutableString
    text.substringWithRange(
      NSRange.new(@startOfInput, text.length - @startOfInput)).to_s
  end

  def readLine
    app = NSApplication.sharedApplication
    @startOfInput = lengthOfTextView
    loop do
      event = app.nextEventMatchingMask(NSAnyEventMask, 
        untilDate: NSDate.distantFuture(), 
        inMode: NSDefaultRunLoopMode, 
        dequeue: true)
      if (event.type == NSKeyDown) and 
         event.window and 
         (event.window.isEqual(@textview.window))
        break if event.characters.to_s == "\r"
        if (event.modifierFlags & NSControlKeyMask) != 0 then
          case event.keyCode
          when '0' then  moveAndScrollToIndex(@startOfInput)     # control-a
          when '14' then moveAndScrollToIndex(lengthOfTextView)  # control-e
          end
        end
      end
      app.sendEvent(event)
    end
    lineToReturn = currentLine
    @startOfInput = lengthOfTextView
    write("\n")
    return lineToReturn + "\n"
  end

  def handleEvents
    app = NSApplication.sharedApplication
    event = app.nextEventMatchingMask(NSAnyEventMask,
      untilDate: NSDate.dateWithTimeIntervalSinceNow(0.01),
      inMode: NSDefaultRunLoopMode,
      dequeue: true)
    if event
      if (event.type == NSKeyDown) and
        event.window and
        (event.window.isEqual(@textview.window)) and
        (event.charactersIgnoringModifiers.to_s == 'c') and
        (event.modifierFlags & NSControlKeyMask)
        raise IRB::Abort, "abort, then interrupt!!" # that's what IRB says...
      else
        app.sendEvent(event)
      end
    end
  end

  def replaceLineWithHistory(s)
    range = NSRange.new(@startOfInput, lengthOfTextView - @startOfInput)
    @textview.textStorage.replaceCharactersInRange(range, withAttributedString: NSAttributedString.alloc.initWithString(s.chomp))
    @textview.scrollRangeToVisible([lengthOfTextView, 0])
    true
  end

  # delegate methods
  def textView(textview, shouldChangeTextInRange: range, replacementString: replacement)
    return false if range.location < @startOfInput
    replacement = replacement.to_s.gsub("\r","\n")
    if replacement.length > 0 and replacement[-1].chr == "\n"
      @textview.textStorage.appendAttributedString(
        NSAttributedString.alloc.initWithString(replacement)
      ) if currentLine != ""
      @startOfInput = lengthOfTextView
      false # don't insert replacement text because we've already inserted it
    else
      true  # caller should insert replacement text
    end
  end

  def textView(textview, willChangeSelectionFromCharacterRange: oldRange, toCharacterRange: newRange)
    return oldRange if (newRange.length == 0) and
                       (newRange.location < @startOfInput)
    newRange
  end

  def textView(textview, doCommandBySelector: selector)
    case selector
    when "moveUp:"
      replaceLineWithHistory(@inputMethod.prevCmd)
    when "moveDown:"
      replaceLineWithHistory(@inputMethod.nextCmd)
    else
      false
    end
  end
end

module IRB
  def IRB.startInConsole(console)
    IRB.setup(nil)
    @CONF[:PROMPT_MODE] = :DEFAULT
    @CONF[:VERBOSE] = false
    @CONF[:ECHO] = true
    irb = Irb.new(nil, console.inputMethod)
    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context
    trap("SIGINT") do
      irb.signal_handle
    end
    old_stdout, old_stderr = $stdout, $stderr
    $stdout = $stderr = console
    catch(:IRB_EXIT) do
      loop do
        begin
          irb.eval_input
        rescue Exception
          puts "Error: #{$!}"
        end
      end
    end
    $stdout, $stderr = old_stdout, old_stderr
  end
  class Context
    def prompting?
      true
    end
  end
end

class ApplicationDelegate
  def applicationDidFinishLaunching(sender)
    $consoleWindowController = ConsoleWindowController.alloc.initWithFrame([50,50,600,300])
    $consoleWindowController.run
  end
end