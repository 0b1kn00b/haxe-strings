/*
 * Copyright (c) 2016-2017 Vegard IT GmbH, http://vegardit.com
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package hx.strings;

import haxe.Utf8;
import haxe.io.Eof;
import haxe.io.Input;
import hx.strings.internal.RingBuffer;

import hx.strings.Strings.CharPos;
import hx.strings.internal.AnyAsString;
import hx.strings.internal.Bits;
import hx.strings.internal.TriState;

using hx.strings.Strings;

/**
 * @author Sebastian Thomschke, Vegard IT GmbH
 */
class CharIterator {

    /**
     * <pre><code>
     * >>> CharIterator.fromString(null).hasNext()          == false
     * >>> CharIterator.fromString("").hasNext()            == false
     * >>> CharIterator.fromString("cat").hasNext()         == true
     * >>> CharIterator.fromString("cat").next().toString() == "c"
     * >>> CharIterator.fromString("はい").next().toString() == "は"
     * </code></pre>
     *
     * @param prevBufferSize number of characters the iterator can go backwards
     */
    inline
    public static function fromString(chars:AnyAsString, prevBufferSize = 0):CharIterator {
        if (chars == null) return NullCharIterator.INSTANCE;
        return new StringCharIterator(chars, prevBufferSize);
    }

    /**
     * <pre><code>
     * >>> CharIterator.fromArray(null).hasNext()                           == false
     * >>> CharIterator.fromArray(Strings.toChars("")).hasNext()            == false
     * >>> CharIterator.fromArray(Strings.toChars("cat")).hasNext()         == true
     * >>> CharIterator.fromArray(Strings.toChars("cat")).next().toString() == "c"
     * >>> CharIterator.fromArray(Strings.toChars("はい")).next().toString() == "は"
     * </code></pre>
     *
     * @param prevBufferSize number of characters the iterator can go backwards
     */
    inline
    public static function fromArray(chars:Array<Char>, prevBufferSize = 0):CharIterator {
        if (chars == null) return NullCharIterator.INSTANCE;
        return new ArrayCharIterator(chars, prevBufferSize);
    }

    /**
     * Read characters from an ASCII or Utf8-encoded input.
     *
     * <pre><code>
     * >>> CharIterator.fromInput(null).hasNext()          == false
     * >>> CharIterator.fromInput(new haxe.io.StringInput("")).hasNext()            == false
     * >>> CharIterator.fromInput(new haxe.io.StringInput("cat")).hasNext()         == true
     * >>> CharIterator.fromInput(new haxe.io.StringInput("cat")).next().toString() == "c"
     * >>> CharIterator.fromInput(new haxe.io.StringInput("はい")).next().toString() == "は"
     * </code></pre>
     *
     * @param prevBufferSize number of characters the iterator can go backwards
     */
    inline
    public static function fromInput(chars:Input, prevBufferSize = 0):CharIterator {
        if (chars == null) return NullCharIterator.INSTANCE;
        return new InputCharIterator(chars, prevBufferSize);
    }

    /**
     * <pre><code>
     * >>> CharIterator.fromIterator(null).hasNext()                                      == false
     * >>> CharIterator.fromIterator(Strings.toChars("").iterator()).hasNext()            == false
     * >>> CharIterator.fromIterator(Strings.toChars("cat").iterator()).hasNext()         == true
     * >>> CharIterator.fromIterator(Strings.toChars("cat").iterator()).next().toString() == "c"
     * >>> CharIterator.fromIterator(Strings.toChars("はい").iterator()).next().toString() == "は"
     * </code></pre>
     *
     * @param prevBufferSize number of characters the iterator can go backwards
     */
    inline
    public static function fromIterator(chars:Iterator<Char>, prevBufferSize = 0):CharIterator {
        if (chars == null) return NullCharIterator.INSTANCE;
        return new IteratorCharIterator(chars, prevBufferSize);
    }

    var index = -1;
    var line = 0;
    var col = 0;
    var currChar = -1;

    var usePrevBuffer:Bool;
    var prevBuffer:RingBuffer<CharWithPos>;
    var prevBufferPrevIdx = -1;
    var prevBufferNextIdx = -1;

    public var pos(get, never):CharPos;
    inline function get_pos() return new CharPos(index, line, col);

    function new (prevBufferSize:Int) {
        if (prevBufferSize > 0) {
            usePrevBuffer = true;
            prevBuffer = new RingBuffer<CharWithPos>(prevBufferSize + 1 /*currChar*/);
        } else {
            usePrevBuffer = false;
        }
    }

    inline
    public function hasPrev():Bool {
        return prevBufferPrevIdx > -1;
    }

    /**
     * Moves to the previous character in the input sequence and returns it.
     *
     * @throws haxe.io.Eof if no previous character is available
     */
    public function prev():Char {

        if (isEOF())
            throw new Eof();

        var prevChar = prevBuffer[prevBufferPrevIdx];
        currChar = prevChar.char;
        index = prevChar.index;
        line = prevChar.line;
        col = prevChar.col;

        prevBufferNextIdx = prevBufferPrevIdx + 1 < prevBuffer.length ? prevBufferPrevIdx + 1 : -1;
        prevBufferPrevIdx--;
        return currChar;
    }

    inline
    public function hasNext():Bool {
        if (prevBufferNextIdx > -1) {
            return true;
        }

        return !isEOF();
    }

    /**
     * Moves to the next character in the input sequence and returns it.
     *
     * @throws haxe.io.Eof if no more characters are available
     */
    @:final
    public function next():Char {

        if (prevBufferNextIdx > -1) {
            var prevChar = prevBuffer[prevBufferNextIdx];
            currChar = prevChar.char;
            index = prevChar.index;
            line = prevChar.line;
            col = prevChar.col;
            prevBufferPrevIdx = prevBufferNextIdx - 1;
            prevBufferNextIdx = prevBufferNextIdx + 1 < prevBuffer.length ? prevBufferNextIdx + 1 : -1;
            return currChar;
        }

        if (isEOF())
            throw new Eof();

        if (currChar == Char.LF || currChar < 0) {
            line++;
            col=0;
        }

        index++;
        col++;
        currChar = getChar();

        if (usePrevBuffer) {
            prevBuffer.add(new CharWithPos(currChar, index, col, line));
            prevBufferPrevIdx = prevBuffer.length - 2;
            prevBufferNextIdx = -1;
        }

        return currChar;
    }

    /**
     * @return the char at the current position
     */
    function getChar():Char throw "Not implemented" ;

    function isEOF():Bool throw "Not implemented";
}


@:noDoc @:dox(hide)
private class CharWithPos extends CharPos {

    public function new(char:Char, index:CharIndex, line:Int, col:Int) {
         super(index, line, col);
         this.char = char;
    }

    public var char(default, null):Char;
}


@:noDoc @:dox(hide)
private class NullCharIterator extends CharIterator {

    public static var INSTANCE = new NullCharIterator();

    function new() {
        super(0);
    }

    override
    function isEOF():Bool {
        return true;
    }
}

@:noDoc @:dox(hide)
private class ArrayCharIterator extends CharIterator {
    var chars:Array<Char>;
    var charsMaxIndex:Int;

    public function new(chars:Array<Char>, prevBufferSize:Int) {
        super(prevBufferSize);
        this.chars = chars;
        charsMaxIndex = chars.length -1;
    }

    override
    function isEOF():Bool {
        return index >= charsMaxIndex;
    }

    override
    function getChar(): Char {
        return chars[index];
    }
}

@:noDoc @:dox(hide)
private class IteratorCharIterator extends CharIterator {
    var chars:Iterator<Char>;

    public function new(chars:Iterator<Char>, prevBufferSize:Int) {
        super(prevBufferSize);
        this.chars = chars;
    }

    override
    function isEOF():Bool {
        return !chars.hasNext();
    }

    override
    function getChar(): Char {
        return chars.next();
    }
}

@:noDoc @:dox(hide)
private class InputCharIterator extends CharIterator {
    var byteIndex = 0;
    var input:Input;
    var currCharIndex = -1;
    var nextChar:Char;
    var nextCharAvailable = TriState.UNKNOWN;

    public function new(chars:Input, prevBufferSize:Int) {
        super(prevBufferSize);
        this.input = chars;
    }

    override
    function isEOF():Bool {
        if (nextCharAvailable == UNKNOWN) {
            try {
                nextChar = readUtf8Char();
                nextCharAvailable = TRUE;
            } catch (ex:haxe.io.Eof) {
                nextCharAvailable = FALSE;
            }
        }
        return nextCharAvailable != TRUE;
    }

    override
    function getChar(): Char {
        if(index != currCharIndex) {
            currCharIndex = index;
            nextCharAvailable = UNKNOWN;
            return nextChar;
        }
        return currChar;
    }

    /**
     * http://www.fileformat.info/info/unicode/utf8.htm
     * @throws exception if an unexpected byte was found
     */
    inline
    function readUtf8Char():Char {
        var byte1 = input.readByte();
        byteIndex++;
        if (byte1 <= 127)
            return byte1;

        /*
         * determine the number of bytes composing this UTF char
         * and clear the control bits from the first byte.
         */
        byte1 = Bits.clearBit(byte1, 8);
        byte1 = Bits.clearBit(byte1, 7);
        var totalBytes = 2;

        var isBit6Set = Bits.getBit(byte1, 6);
        var isBit5Set = false;
        if(isBit6Set) {
            byte1 = Bits.clearBit(byte1, 6);
            totalBytes++;

            isBit5Set = Bits.getBit(byte1, 5);
            if(isBit5Set) {
                byte1 = Bits.clearBit(byte1, 5);
                totalBytes++;

                if (Bits.getBit(byte1, 4))
                    throw 'Valid UTF-8 byte expected at position [$byteIndex] but found byte with value [$byte]!';
            }
        }

        var result:Int = (byte1 << 6*(totalBytes-1));

        /*
         * read the second byte
         */
        var byte2 = readUtf8MultiSequenceByte();
        result += (byte2 << 6*(totalBytes-2));

        /*
         * read the third byte
         */
        if(isBit6Set) {
            var byte3 = readUtf8MultiSequenceByte();
            result += (byte3 << 6*(totalBytes-3));

            /*
             * read the fourth byte
             */
            if(isBit5Set) {
                var byte4 = readUtf8MultiSequenceByte();
                result += (byte4 << 6*(totalBytes-4));
            }
        }

        // UTF8-BOM marker http://unicode.org/faq/utf_bom.html#bom4
        if (index == 0 && result == 65279)
            return readUtf8Char();

        return result;
    }

    inline
    function readUtf8MultiSequenceByte():Int {
        var byte = input.readByte();
        byteIndex++;

        if (!Bits.getBit(byte, 8))
            throw 'Valid UTF-8 multi-sequence byte expected at position [$byteIndex] but found byte with value [$byte]!';

        if (Bits.getBit(byte, 7))
            throw 'Valid UTF-8 multi-sequence byte expected at position [$byteIndex] but found byte with value [$byte]!';

        return Bits.clearBit(byte, 8);
    }
}

@:noDoc @:dox(hide)
private class StringCharIterator extends CharIterator {
    var chars:String;
    var charsMaxIndex:Int;

    public function new(chars:String, prevBufferSize:Int) {
        super(prevBufferSize);
        this.chars = chars;
        charsMaxIndex = chars.length8() - 1;
    }

    override
    function isEOF():Bool {
        return index >= charsMaxIndex;
    }

    override
    function getChar(): Char {
        return Strings._charCodeAt8Unsafe(chars, index);
    }
}
