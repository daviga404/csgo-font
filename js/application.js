// Generated by CoffeeScript 1.8.0
(function() {
  var ByteBuffer, CSMTextSettingsTag, DefineEditTextTag, DefineFont3Tag, TTFException, TTFReader, Tag, Utils,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  ByteBuffer = dcodeIO.ByteBuffer;

  Utils = {
    pad: function(str, len) {
      return (Array(len - str.length + 1).join('0')) + str;
    },
    toFixed: function(num) {
      return (num >> 16) + (num & 0xFFFF) * Math.pow(2, -16);
    },
    toF2Dot14: function(num) {
      return (num >> 14) + (num & 0x3FFF) * Math.pow(2, -14);
    }
  };

  Tag = (function() {

    /**
     * Constructs a basic tag with tag code `id`. Note that
     * this MUST be called by subclasses in order to properly 
     * initialize the body buffer.
     *
     * @param {Number} id The tag's code/id.
     */
    function Tag(id) {
      this.id = id;
      this.body = new ByteBuffer(1, ByteBuffer.LITTLE_ENDIAN);
    }


    /**
     * Writes this tag, along with its code and length, to a ByteBuffer.
     * @param {ByteBuffer} buffer The target buffer to write to.
     */

    Tag.prototype.write = function(buffer) {
      var idAndLength;
      idAndLength = (this.id & 0x3FF) << 6;
      idAndLength |= this.body.offset >= 0x3F ? 0x3F : this.body.offset;
      buffer.writeUint16(idAndLength);
      if (idAndLength & 0x3F === 0x3F) {
        buffer.writeUint32(this.body.offset);
      }
      return buffer.append(this.body);
    };


    /**
     * Writes a RECT type to the body of the tag.
     * @param {Array} rect An array of [xMin, xMax, yMin, yMax]
     */

    Tag.prototype.writeRect = function(rect) {
      var binaryString, bitString, bits, coord, i, _i;
      bitString = "";
      bits = Math.max.apply(Math, (function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = rect.length; _i < _len; _i++) {
          coord = rect[_i];
          _results.push(coord.toString(2).length);
        }
        return _results;
      })());
      bitString += Utils.pad(bits.toString(2), 5);
      for (i = _i = 0; _i <= 3; i = ++_i) {
        bitString += Utils.pad(rect[i].toString(2).replace(/[^0-9]/g, ''), bits);
      }
      if (bitString.length % 8 !== 0) {
        bitString += Array(8 - bitString.length % 8 + 1).join('0');
      }
      binaryString = ((function() {
        var _j, _ref, _results;
        _results = [];
        for (i = _j = 0, _ref = bitString.length - 1; _j <= _ref; i = _j += 8) {
          _results.push(String.fromCharCode(parseInt(bitString.substring(i, i + 8), 2)));
        }
        return _results;
      })()).join('');
      return this.body.append(binaryString, 'binary');
    };


    /**
     * Writes RGBA data to the body of the tag.
     *
     * @param {Number} red   Red value
     * @param {Number} green Green value
     * @param {Number} blue  Blue value
     * @param {Number} alpha Alpha value
     */

    Tag.prototype.writeRGBA = function(red, green, blue, alpha) {
      this.body.writeUint8(red);
      this.body.writeUint8(green);
      this.body.writeUint8(blue);
      return this.body.writeUint8(alpha);
    };

    return Tag;

  })();

  DefineEditTextTag = (function(_super) {
    __extends(DefineEditTextTag, _super);


    /**
     * Constructs a new DefineEditText tag. Required settings:
     * - settings.characterId: ID for this EditText
     * - settings.bounds:      The bounds of the EditText
     *
     * @param {Object} settings An object of settings. See the SWF file specification
     *                          for names and function of these settings. Names are camelCase
     *                          and start with a lower-case letter.
     */

    function DefineEditTextTag(settings) {
      DefineEditTextTag.__super__.constructor.call(this, 37);
      this.body.writeUint16(settings.characterId);
      this.writeRect(settings.bounds);
      this.body.writeUint8(settings.hasText << 7 | settings.wordWrap << 6 | settings.multiline << 5 | settings.password << 4 | settings.readOnly << 3 | settings.hasTextColor << 2 | settings.hasMaxLength << 1 | settings.hasFont);
      this.body.writeUint8(settings.hasFontClass << 7 | settings.autoSize << 6 | settings.hasLayout << 5 | settings.noSelect << 4 | settings.border << 3 | settings.wasStatic << 2 | settings.html << 1 | settings.useOutlines);
      this.body.writeCString(settings.variableName || '');
      if (settings.hasFont) {
        this.body.writeUint16(settings.fontId);
      }
      if (settings.hasFontClass) {
        this.body.writeCString(settings.fontClass);
      }
      if (settings.hasFont) {
        this.body.writeUint16(settings.fontHeight);
      }
      if (settings.hasTextColor) {
        this.writeRGBA.apply(this, settings.textColor);
      }
      if (settings.hasMaxLength) {
        this.body.writeUint16(settings.maxLength);
      }
      if (settings.hasLayout) {
        this.body.writeUint8(settings.align);
      }
      if (settings.hasLayout) {
        this.body.writeUint16(settings.leftMargin);
      }
      if (settings.hasLayout) {
        this.body.writeUint16(settings.rightMargin);
      }
      if (settings.hasLayout) {
        this.body.writeUint16(settings.indent);
      }
      if (settings.hasLayout) {
        this.body.writeInt16(settings.leading);
      }
      if (settings.hasText) {
        this.body.writeCString(settings.initialText);
      }
    }

    return DefineEditTextTag;

  })(Tag);

  CSMTextSettingsTag = (function(_super) {
    __extends(CSMTextSettingsTag, _super);

    function CSMTextSettingsTag(textId, useFlashType, gridFit, thickness, sharpness) {
      CSMTextSettingsTag.__super__.constructor.call(this, 74);
      this.body.writeUint16(textId);
      this.body.writeUint8(useFlashType << 6 | gridFit << 3);
      this.body.writeFloat32(thickness);
      this.body.writeFloat32(sharpness);
      this.body.writeUint8(0);
    }

    return CSMTextSettingsTag;

  })(Tag);

  DefineFont3Tag = (function(_super) {
    var TTF_HEAD, TTF_HHEA;

    __extends(DefineFont3Tag, _super);

    TTF_HHEA = 0x68686561;

    TTF_HEAD = 0x68656164;


    /**
     * Constructs a new DefineFont3 tag. This should
     * be instantiated with a ByteBuffer, `ttfBuffer`,
     * that contains the TTF data for this font tag.
     *
     * @param {ByteBuffer} ttfBuffer       Buffer of TTF data
     * @param {Number}     settings.fontId The ID to use for this font (required)
     * @throws {TTFException} If the TTF file was invalid
     */

    function DefineFont3Tag(ttfBuffer, settings) {
      var reader;
      DefineFont3Tag.__super__.constructor.call(this, 75);
      reader = new TTFReader(ttfBuffer);
      reader.read();
      this.body.writeUint16(settings.fontId);
      this.body.writeUint8(0x80 | 0 | 0 | 0);
      console.log(reader.encodingTables);
    }

    return DefineFont3Tag;

  })(Tag);

  TTFException = (function(_super) {
    __extends(TTFException, _super);

    function TTFException(message) {
      this.message = message;
      this.name = 'TTFException';
    }

    return TTFException;

  })(Error);

  TTFReader = (function() {
    var FLAG_ARGS_ARE_XY_VALUES, FLAG_ARG_1_AND_2_ARE_WORDS, FLAG_BIT_0, FLAG_BIT_1, FLAG_BIT_2, FLAG_BIT_3, FLAG_BIT_4, FLAG_BIT_5, FLAG_BIT_6, FLAG_BIT_7, FLAG_BIT_8, FLAG_BIT_9, FLAG_MORE_COMPONENTS, FLAG_ON_CURVE, FLAG_REPEAT, FLAG_ROUND_XY_TO_GRID, FLAG_USE_MY_METRICS, FLAG_WE_HAVE_AN_XY_SCALE, FLAG_WE_HAVE_A_SCALE, FLAG_WE_HAVE_A_TWO_BY_TWO, FLAG_WE_HAVE_INSTRUCTIONS, FLAG_X_IS_BYTE, FLAG_X_IS_SAME, FLAG_Y_IS_BYTE, FLAG_Y_IS_SAME, FORMAT_LONG, FORMAT_SHORT, GLYPH_TYPE_COMPOUND, GLYPH_TYPE_SINGLE, TTF_CMAP, TTF_GLYF, TTF_HEAD, TTF_HHEA, TTF_LOCA, TTF_MAXP;

    TTF_HHEA = 0x68686561;

    TTF_HEAD = 0x68656164;

    TTF_GLYF = 0x676C7966;

    TTF_CMAP = 0x636D6170;

    TTF_LOCA = 0x6C6F6361;

    TTF_MAXP = 0x6D617870;

    FLAG_BIT_0 = 0x1;

    FLAG_BIT_1 = 0x2;

    FLAG_BIT_2 = 0x4;

    FLAG_BIT_3 = 0x8;

    FLAG_BIT_4 = 0x10;

    FLAG_BIT_5 = 0x20;

    FLAG_BIT_6 = 0x40;

    FLAG_BIT_7 = 0x80;

    FLAG_BIT_8 = 0x100;

    FLAG_BIT_9 = 0x200;

    FLAG_ON_CURVE = FLAG_BIT_0;

    FLAG_X_IS_BYTE = FLAG_BIT_1;

    FLAG_Y_IS_BYTE = FLAG_BIT_2;

    FLAG_REPEAT = FLAG_BIT_3;

    FLAG_X_IS_SAME = FLAG_BIT_4;

    FLAG_Y_IS_SAME = FLAG_BIT_5;

    FLAG_ARG_1_AND_2_ARE_WORDS = FLAG_BIT_0;

    FLAG_ARGS_ARE_XY_VALUES = FLAG_BIT_1;

    FLAG_ROUND_XY_TO_GRID = FLAG_BIT_2;

    FLAG_WE_HAVE_A_SCALE = FLAG_BIT_3;

    FLAG_MORE_COMPONENTS = FLAG_BIT_5;

    FLAG_WE_HAVE_AN_XY_SCALE = FLAG_BIT_6;

    FLAG_WE_HAVE_A_TWO_BY_TWO = FLAG_BIT_7;

    FLAG_WE_HAVE_INSTRUCTIONS = FLAG_BIT_8;

    FLAG_USE_MY_METRICS = FLAG_BIT_9;

    FORMAT_SHORT = 0;

    FORMAT_LONG = 1;

    GLYPH_TYPE_SINGLE = 'single';

    GLYPH_TYPE_COMPOUND = 'compound';

    function TTFReader(data) {
      this.data = data.clone();
      this.tables = {};
      this.info = {};
      this.glyphs = [];
      this.encodingTables = [];
    }

    TTFReader.prototype.read = function() {
      var i, numTables, sfntVersion, _i, _ref;
      this.data.reset();
      sfntVersion = Utils.toFixed(this.data.readInt32());
      if (sfntVersion === !1.0) {
        throw new TTFException('Invalid SFNT version in TTF file');
      }
      numTables = this.data.readUint16();
      this.data.skip(6);
      for (i = _i = 0, _ref = numTables - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        this.tables[this.data.readUint32()] = {
          checkSum: this.data.readUint32(),
          offset: this.data.readUint32(),
          length: this.data.readUint32()
        };
      }
      this.readInfo();
      this.readGlyphs();
      return this.readCmapTable();
    };

    TTFReader.prototype.readInfo = function() {

      /*
       * Read 'head' table
       */
      var headBuff, macStyle, maxpBuff;
      headBuff = this.getTable(TTF_HEAD);
      if (!headBuff) {
        throw new TTFException('Required head table not found in TTF file');
      }
      this.info.head = {};
      this.info.head.version = Utils.toFixed(headBuff.readUint32());
      this.info.head.fontRevision = Utils.toFixed(headBuff.readUint32());
      this.info.head.checkSumAdjustment = headBuff.readUint32();
      this.info.head.magicNumber = headBuff.readUint32();
      this.info.head.flags = headBuff.readUint16();
      this.info.head.unitsPerEm = headBuff.readUint16();
      headBuff.skip(16);
      this.info.head.xMin = headBuff.readUint16();
      this.info.head.yMin = headBuff.readUint16();
      this.info.head.xMax = headBuff.readUint16();
      this.info.head.yMax = headBuff.readUint16();
      macStyle = headBuff.readUint16();
      this.info.head.bold = !!(macStyle & FLAG_BIT_0);
      this.info.head.italic = !!(macStyle & FLAG_BIT_1);
      this.info.head.lowestRecPPEM = headBuff.readUint16();
      this.info.head.fontDirectionHint = headBuff.readInt16();
      this.info.head.indexToLocFormat = headBuff.readInt16();
      this.info.head.glyphDataFormat = headBuff.readInt16();

      /*
       * Read 'maxp' table
       */
      maxpBuff = this.getTable(TTF_MAXP);
      if (!maxpBuff) {
        throw new TTFException('Required maxp table not found in TTF file');
      }
      maxpBuff.skip(4);
      this.info.maxp = {};
      this.info.maxp.numGlyphs = maxpBuff.readUint16();
      this.info.maxp.maxPoints = maxpBuff.readUint16();
      this.info.maxp.maxContours = maxpBuff.readUint16();
      this.info.maxp.maxCompositePoints = maxpBuff.readUint16();
      this.info.maxp.maxCompositeContours = maxpBuff.readUint16();
      this.info.maxp.maxZones = maxpBuff.readUint16();
      this.info.maxp.maxTwilightPoints = maxpBuff.readUint16();
      this.info.maxp.maxStorage = maxpBuff.readUint16();
      this.info.maxp.maxFunctionDefs = maxpBuff.readUint16();
      this.info.maxp.maxInstructionDefs = maxpBuff.readUint16();
      this.info.maxp.maxStackElements = maxpBuff.readUint16();
      this.info.maxp.maxSizeOfInstructions = maxpBuff.readUint16();
      this.info.maxp.maxComponentElements = maxpBuff.readUint16();
      return this.info.maxp.maxComponentDepth = maxpBuff.readUint16();
    };

    TTFReader.prototype.readCmapTable = function() {
      var cmapTable, encTables, i, numEncTables, offset, platEncoding, platId, subtable, tableStart, _i;
      cmapTable = this.getTable(TTF_CMAP);
      if (!cmapTable) {
        throw new TTFException('Required cmap table not found in TTF file');
      }
      tableStart = cmapTable.offset;
      cmapTable.skip(2);
      numEncTables = cmapTable.readUint16();
      encTables = [];
      for (i = _i = 0; 0 <= numEncTables ? _i < numEncTables : _i > numEncTables; i = 0 <= numEncTables ? ++_i : --_i) {
        platId = cmapTable.readUint16();
        platEncoding = cmapTable.readUint16();
        offset = cmapTable.readUint32();
        subtable = cmapTable.slice(tableStart + offset);
        encTables.push({
          platformId: platId,
          platformEncoding: platEncoding,
          glyphIndexes: this.readCmapSubtable(subtable)
        });
      }
      return this.encodingTables = encTables;
    };

    TTFReader.prototype.readCmapSubtable = function(buffer) {
      var format, length;
      format = buffer.readUint16();
      length = buffer.readUint16();
      switch (format) {
        case 4:
          return this.processCmapFormat4(buffer);
        case 6:
          return this.processCmapFormat6(buffer);
        case 12:
          return this.processCmapFormat12(buffer);
        default:
          return [];
      }
    };

    TTFReader.prototype.processCmapFormat4 = function(buffer) {
      var glyphIndexes, i, j, offset, segCount, segments, _i, _j, _k, _l, _m, _n, _ref, _ref1, _ref2, _ref3;
      glyphIndexes = [];
      segments = [];
      buffer.skip(2);
      segCount = buffer.readUint16() / 2;
      buffer.skip(6);
      for (i = _i = 0; 0 <= segCount ? _i < segCount : _i > segCount; i = 0 <= segCount ? ++_i : --_i) {
        segments.push({
          endCode: buffer.readUint16()
        });
      }
      buffer.skip(2);
      for (i = _j = 0; 0 <= segCount ? _j < segCount : _j > segCount; i = 0 <= segCount ? ++_j : --_j) {
        segments[i].startCode = buffer.readUint16();
      }
      for (i = _k = 0; 0 <= segCount ? _k < segCount : _k > segCount; i = 0 <= segCount ? ++_k : --_k) {
        segments[i].idDelta = buffer.readUint16();
      }
      for (i = _l = 0; 0 <= segCount ? _l < segCount : _l > segCount; i = 0 <= segCount ? ++_l : --_l) {
        offset = buffer.offset;
        segments[i].idRangeOffset = buffer.readUint16();
        if (segments[i].idRangeOffset === 0) {
          for (j = _m = _ref = segments[i].startCode, _ref1 = segments[i].endCode; _ref <= _ref1 ? _m <= _ref1 : _m >= _ref1; j = _ref <= _ref1 ? ++_m : --_m) {
            glyphIndexes[j] = (j + segments[i].idDelta) % 65536;
          }
        } else {
          for (j = _n = _ref2 = segments[i].startCode, _ref3 = segments[i].endCode; _ref2 <= _ref3 ? _n <= _ref3 : _n >= _ref3; j = _ref2 <= _ref3 ? ++_n : --_n) {
            glyphIndexes[j] = buffer.readUint16(offset + 2 * (j - segments[i].startCode));
          }
        }
      }
      return glyphIndexes;
    };

    TTFReader.prototype.processCmapFormat6 = function(buffer) {
      var entryCount, firstCode, glyphIndexes, i, _i, _ref;
      buffer.skip(2);
      firstCode = buffer.readUint16();
      entryCount = buffer.readUint16();
      glyphIndexes = [];
      for (i = _i = firstCode, _ref = firstCode + entryCount; firstCode <= _ref ? _i < _ref : _i > _ref; i = firstCode <= _ref ? ++_i : --_i) {
        glyphIndexes.push(buffer.readUint16());
      }
      return glyphIndexes;
    };

    TTFReader.prototype.processCmapFormat12 = function(buffer) {
      var endCharCode, glyphDiff, glyphIndexes, i, j, nGroups, startCharCode, startGlyphCode, _i, _j;
      buffer.skip(8);
      nGroups = buffer.readUint32();
      glyphIndexes = [];
      for (i = _i = 0; 0 <= nGroups ? _i < nGroups : _i > nGroups; i = 0 <= nGroups ? ++_i : --_i) {
        startCharCode = buffer.readUint32();
        endCharCode = buffer.readUint32();
        startGlyphCode = buffer.readUint32();
        glyphDiff = startGlyphCode - startCharCode;
        for (j = _j = startCharCode; startCharCode <= endCharCode ? _j <= endCharCode : _j >= endCharCode; j = startCharCode <= endCharCode ? ++_j : --_j) {
          glyphIndexes[j] = j + glyphDiff;
        }
      }
      return glyphIndexes;
    };

    TTFReader.prototype.readGlyphs = function() {
      var glyfTable, i, locaTable, multiplier, offset, offsets, readOffset, _i, _j, _ref, _ref1, _results;
      locaTable = this.getTable(TTF_LOCA);
      if (!locaTable) {
        throw new TTFException('Required loca table not found in TTF file');
      }
      offsets = [];
      readOffset = this.info.head.indexToLocFormat === FORMAT_SHORT ? ByteBuffer.prototype.readUint16 : ByteBuffer.prototype.readUint32;
      multiplier = this.info.head.indexToLocFormat === FORMAT_SHORT ? 2 : 1;
      for (i = _i = 0, _ref = this.info.maxp.numGlyphs; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        offsets.push(readOffset.apply(locaTable) * multiplier);
      }
      glyfTable = this.getTable(TTF_GLYF);
      if (!glyfTable) {
        throw new TTFException('Required glyf table not found in TTF file');
      }
      _results = [];
      for (i = _j = 0, _ref1 = this.info.maxp.numGlyphs; 0 <= _ref1 ? _j < _ref1 : _j > _ref1; i = 0 <= _ref1 ? ++_j : --_j) {
        offset = glyfTable.offset + offsets[i];
        _results.push(this.glyphs.push(this.readGlyph(glyfTable.slice(offset))));
      }
      return _results;
    };

    TTFReader.prototype.readGlyph = function(buffer) {
      var glyph;
      glyph = {};
      glyph.numberOfContours = buffer.readInt16();
      glyph.xMin = buffer.readInt16();
      glyph.yMin = buffer.readInt16();
      glyph.xMax = buffer.readInt16();
      glyph.yMax = buffer.readInt16();
      if (glyph.numberOfContours >= 0) {
        this.readSingleGlyph(glyph, buffer);
      } else if (glyph.numberOfContours === -1) {
        this.readCompoundGlyph(glyph, buffer);
      } else {
        throw new TTFException('Invalid number of contours while reading glyph');
      }
      return glyph;
    };

    TTFReader.prototype.readSingleGlyph = function(glyph, buffer) {
      var flag, flags, i, numberOfPoints, readCoords, repeats, _i, _j, _ref;
      glyph.type = GLYPH_TYPE_SINGLE;
      glyph.endpointIndexes = [];
      glyph.points = [];
      for (i = _i = 0, _ref = glyph.numberOfContours; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
        glyph.endpointIndexes.push(buffer.readUint16());
      }
      numberOfPoints = (Math.max.apply(Math, glyph.endpointIndexes)) + 1;
      buffer.skip(buffer.readUint16());
      if (glyph.numberOfContours === 0) {
        return;
      }
      flags = [];
      i = 0;
      while (i < numberOfPoints) {
        flag = buffer.readUint8();
        flags.push(flag);
        glyph.points.push({
          onCurve: flag & FLAG_ON_CURVE > 0
        });
        if (flag & FLAG_REPEAT) {
          repeats = buffer.readUint8();
          i += repeats;
          for (_j = 0; 0 <= repeats ? _j < repeats : _j > repeats; 0 <= repeats ? _j++ : _j--) {
            flags.push(flag);
            glyph.points.push({
              onCurve: flag & FLAG_ON_CURVE > 0
            });
          }
        }
        i++;
      }
      readCoords = function(axis, byteFlag, sameFlag) {
        var value, _k, _ref1, _results;
        value = 0;
        _results = [];
        for (i = _k = 0, _ref1 = glyph.points.length; 0 <= _ref1 ? _k < _ref1 : _k > _ref1; i = 0 <= _ref1 ? ++_k : --_k) {
          flag = flags[i];
          if (flag & byteFlag) {
            value += (flag & sameFlag ? 1 : -1) * buffer.readUint8();
          } else if ((~flag) & sameFlag) {
            value += buffer.readInt16();
          }
          _results.push(glyph.points[i][axis] = value);
        }
        return _results;
      };
      readCoords('x', FLAG_X_IS_BYTE, FLAG_X_IS_SAME);
      return readCoords('y', FLAG_Y_IS_BYTE, FLAG_Y_IS_SAME);
    };

    TTFReader.prototype.readCompoundGlyph = function(glyph, buffer) {
      var argument1, argument2, component, flags;
      glyph.type = GLYPH_TYPE_COMPOUND;
      glyph.components = [];
      flags = 0;
      while (true) {
        component = {
          flags: buffer.readUint16(),
          glyphIndex: buffer.readUint16(),
          matrix: {
            a: 1,
            b: 0,
            c: 0,
            d: 1,
            e: 0,
            f: 0
          }
        };
        flags = component.flags;
        argument1 = flags & FLAG_ARG_1_AND_2_ARE_WORDS ? buffer.readUint16() : buffer.readUint8();
        argument2 = flags & FLAG_ARG_1_AND_2_ARE_WORDS ? buffer.readUint16() : buffer.readUint8();
        if (flags & FLAG_ARGS_ARE_XY_VALUES) {
          component.matrix.e = argument1;
          component.matrix.f = argument2;
        } else {
          component.srcPoint = argument1;
          component.dstPoint = argument2;
        }
        if (flags & FLAG_WE_HAVE_A_SCALE) {
          component.matrix.a = Utils.toF2Dot14(buffer.readUint16());
          component.matrix.d = component.matrix.d;
        } else if (flags & FLAG_WE_HAVE_AN_XY_SCALE) {
          component.matrix.a = Utils.toF2Dot14(buffer.readUint16());
          component.matrix.d = Utils.toF2Dot14(buffer.readUint16());
        } else if (flags & FLAG_WE_HAVE_A_TWO_BY_TWO) {
          component.matrix.a = Utils.toF2Dot14(buffer.readUint16());
          component.matrix.b = Utils.toF2Dot14(buffer.readUint16());
          component.matrix.c = Utils.toF2Dot14(buffer.readUint16());
          component.matrix.d = Utils.toF2Dot14(buffer.readUint16());
        }
        glyph.components.push(component);
        if (!(flags & FLAG_MORE_COMPONENTS)) {
          break;
        }
      }
      if (flags & FLAG_WE_HAVE_INSTRUCTIONS) {
        return buffer.skip(buffer.readUint16());
      }
    };

    TTFReader.prototype.getTable = function(name) {
      var length, offset;
      if (this.tables.hasOwnProperty(name)) {
        offset = this.tables[name].offset;
        length = this.tables[name].length;
        return this.data.slice(offset, offset + length);
      }
      return null;
    };


    /*
     * Gets loaded information about the font. The data is returned
     * as an object, indexed by keys of the tables (e.g. 'head', 'maxp').
     * The values of these keys are also objects, with keys as their
     * camelCase equivalents to those in the TTF specification.
     *
     * Currently, the tables loaded in font info are 'head', and 'maxp'
     *
     * @return {Object}
     */

    TTFReader.prototype.getFontInfo = function() {
      return this.info;
    };

    TTFReader.prototype.getGlyphs = function() {
      return this.glyphs;
    };

    TTFReader.prototype.getGlyph = function(charId) {
      return null;
    };

    return TTFReader;

  })();

  window.addEventListener('load', function() {
    var form;
    form = document.getElementById('ttf-upload');
    return form.addEventListener('submit', function(e) {
      var file, fileReader;
      e.preventDefault();
      if (e.target.ttf.files.length < 1) {
        alert('Please upload a file!');
      }
      file = e.target.ttf.files[0];
      fileReader = new FileReader();
      fileReader.addEventListener('load', function() {
        var buff, fontBuff, glyphIndex, key, table, ttfReader, _i, _j, _len, _len1, _ref, _ref1;
        buff = fileReader.result;
        fontBuff = ByteBuffer.wrap(buff);
        ttfReader = new TTFReader(fontBuff);
        ttfReader.read();
        console.log('Trying to do A character...');
        glyphIndex = -1;
        _ref = ttfReader.encodingTables;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          table = _ref[_i];
          if (table.platformId === 3 && table.platformEncoding === 1) {
            _ref1 = table.glyphIndexes;
            for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
              key = _ref1[_j];
              if (table.glyphIndexes[key] === 0) {
                console.log(key);
              }
            }
            if (__indexOf.call(table.glyphIndexes, 65) >= 0) {
              glyphIndex = table.glyphIndexes[65];
            }
          }
        }
        console.log(glyphIndex);
        console.log(ttfReader.getGlyphs());
        return console.log('Success!');
      });
      return fileReader.readAsArrayBuffer(file);
    });
  });

}).call(this);