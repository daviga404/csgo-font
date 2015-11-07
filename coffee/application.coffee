ByteBuffer = dcodeIO.ByteBuffer
Utils      =
    # Pads a number (in string form) to `len` digits.
    pad: (str, len) -> (Array(len - str.length + 1).join '0') + str

    # Converts a 32 bit int into a fixed point number (16.16)
    toFixed: (num) -> (num >> 16) + (num & 0xFFFF) * Math.pow(2, -16)

class Tag

    ###*
    # Constructs a basic tag with tag code `id`. Note that
    # this MUST be called by subclasses in order to properly 
    # initialize the body buffer.
    #
    # @param {Number} id The tag's code/id.
    ###
    constructor: (@id) ->
        @body = new ByteBuffer(1, ByteBuffer.LITTLE_ENDIAN)

    ###*
    # Writes this tag, along with its code and length, to a ByteBuffer.
    # @param {ByteBuffer} buffer The target buffer to write to.
    ###
    write: (buffer) ->
        # Work out TagCodeAndLength (first 10 bits = tag code, last 6 = length)
        # If length is > 0x3F, we need a long RECORDHEADER.
        idAndLength  = (@id & 0x3FF) << 6                                   # 10 bits; shift left to align with uint16
        idAndLength |= if @body.offset >= 0x3F then 0x3F else @body.offset  # Use special 0x3F value if >=63 bytes long 

        buffer.writeUint16 idAndLength

        # Write the length as a uint32, if too long
        if idAndLength & 0x3F == 0x3F
            buffer.writeUint32 @body.offset

        # Write the body of the tag
        buffer.append @body

    ###*
    # Writes a RECT type to the body of the tag.
    # @param {Array} rect An array of [xMin, xMax, yMin, yMax]
    ###
    writeRect: (rect) ->
        bitString = ""
        bits      = (Math.max (coord.toString(2).length for coord in rect)...) # Get the maximum bit length

        # Append bit length to the bitString
        bitString += Utils.pad bits.toString(2), 5

        # Append each coord [in order], padding to `bits` bit
        for i in [0..3]
            bitString += Utils.pad rect[i].toString(2).replace(/[^0-9]/g, ''), bits

        # Byte-align the string
        if bitString.length % 8 != 0
            bitString += Array(8 - bitString.length % 8 + 1).join '0'

        # Generate a binary string by splitting every 8 
        binaryString = (String.fromCharCode(
                parseInt(
                    bitString.substring(i, i + 8),
                    2
                )
            ) for i in [0..bitString.length-1] by 8)
            .join ''

        # Finally, write it
        @body.append binaryString, 'binary'

    ###*
    # Writes RGBA data to the body of the tag.
    #
    # @param {Number} red   Red value
    # @param {Number} green Green value
    # @param {Number} blue  Blue value
    # @param {Number} alpha Alpha value
    ###
    writeRGBA: (red, green, blue, alpha) ->
        @body.writeUint8 red
        @body.writeUint8 green
        @body.writeUint8 blue
        @body.writeUint8 alpha


class DefineEditTextTag extends Tag

    ###*
    # Constructs a new DefineEditText tag. Required settings:
    # - settings.characterId: ID for this EditText
    # - settings.bounds:      The bounds of the EditText
    #
    # @param {Object} settings An object of settings. See the SWF file specification
    #                          for names and function of these settings. Names are camelCase
    #                          and start with a lower-case letter.
    ###
    constructor: (settings) ->
        super 37 # Tag type = 37

        @body.writeUint16 settings.characterId
        this.writeRect settings.bounds

        # Write each setting as a single bit... 
        # They must be written as octets because the
        # little endianness will override the order if
        # written as Uint16s.
        @body.writeUint8 (settings.hasText << 7 |
           settings.wordWrap     << 6 |
           settings.multiline    << 5 |
           settings.password     << 4 |
           settings.readOnly     << 3 |
           settings.hasTextColor << 2 |
           settings.hasMaxLength << 1 |
           settings.hasFont)
        @body.writeUint8 (settings.hasFontClass << 7 |
            settings.autoSize  << 6 |
            settings.hasLayout << 5 |
            settings.noSelect  << 4 | 
            settings.border    << 3 | 
            settings.wasStatic << 2 |
            settings.html      << 1 |
            settings.useOutlines)

        # Write all of the other settings; most of these are optional, 
        # and only apply if another setting is true. See the SWF specification
        # for further information.
        @body.writeCString (settings.variableName || '')
        @body.writeUint16  settings.fontId       if settings.hasFont
        @body.writeCString settings.fontClass    if settings.hasFontClass
        @body.writeUint16  settings.fontHeight   if settings.hasFont
        this.writeRGBA     settings.textColor... if settings.hasTextColor
        @body.writeUint16  settings.maxLength    if settings.hasMaxLength
        @body.writeUint8   settings.align        if settings.hasLayout
        @body.writeUint16  settings.leftMargin   if settings.hasLayout
        @body.writeUint16  settings.rightMargin  if settings.hasLayout
        @body.writeUint16  settings.indent       if settings.hasLayout
        @body.writeInt16   settings.leading      if settings.hasLayout
        @body.writeCString settings.initialText  if settings.hasText

class CSMTextSettingsTag extends Tag

    constructor: (textId, useFlashType, gridFit, thickness, sharpness) ->
        super 74 # Tag type = 74

        @body.writeUint16 textId
        @body.writeUint8 (
            useFlashType << 6 | # UseFlashType is 2 bits
            gridFit      << 3   # GridFit is 3 bits
            # Reserved for 3 bits
        )
        @body.writeFloat32 thickness
        @body.writeFloat32 sharpness
        @body.writeUint8 0 # Reserved

class DefineFont3Tag extends Tag

    # Constants
    TTF_HHEA = 0x68686561 # TTF horizontal header table ID
    TTF_HEAD = 0x68656164 # TTF head table

    ###*
    # Constructs a new DefineFont3 tag. This should
    # be instantiated with a ByteBuffer, `ttfBuffer`,
    # that contains the TTF data for this font tag.
    #
    # @param {ByteBuffer} ttfBuffer       Buffer of TTF data
    # @param {Number}     settings.fontId The ID to use for this font (required)
    # @throws {TTFException} If the TTF file was invalid
    ###
    constructor: (ttfBuffer, settings) ->
        super 75 # Tag type = 75

        reader = new TTFReader(ttfBuffer)
        reader.read()

        @body.writeUint16 settings.fontId
        @body.writeUint8 (
            0x80 | # flagsHasLayout = 1
            0    | # flagsShiftJIS  = 0 (TODO: add support for ShiftJIS)
            0    | # flagsSmallText = 0
            # TODO
        )

class TTFException extends Error
    constructor: (@message) ->
        @name = 'TTFException'

class TTFReader

    # Constants
    TTF_HHEA = 0x68686561 # Horizontal header table
    TTF_HEAD = 0x68656164 # Head table
    TTF_GLYF = 0x676C7966 # Glyf (glyph) table
    TTF_CMAP = 0x636D6170 # Cmap (character mapping) table

    # Bitmask constants
    FLAG_BIT_0 = 0x1
    FLAG_BIT_1 = 0x2
    FLAG_BIT_2 = 0x4
    FLAG_BIT_3 = 0x8
    FLAG_BIT_4 = 0x10
    FLAG_BIT_5 = 0x20
    FLAG_BIT_6 = 0x40
    FLAG_BIT_7 = 0x80

    # Single glyph flags
    FLAG_ON_CURVE  = FLAG_BIT_0
    FLAG_X_IS_BYTE = FLAG_BIT_1
    FLAG_Y_IS_BYTE = FLAG_BIT_2
    FLAG_REPEAT    = FLAG_BIT_3
    FLAG_X_IS_SAME = FLAG_BIT_4
    FLAG_Y_IS_SAME = FLAG_BIT_5

    constructor: (data) ->
        @data   = data.clone() # ByteBuffer of the raw TTF data
        @tables = {}           # Tables in file, indexed by their IDs
        @head   = {}           # Head information in TTF; keys correspond to their camelCase equivalent in the TTF specification
        @glyphs = []           # Array of glyphs in the TTF file [TODO]

    read: ->
        @data.reset()

        # SFNT Version is fixed point (16.16)
        sfntVersion = Utils.toFixed @data.readInt32()

        if sfntVersion is not 1.0
            throw new TTFException('Invalid SFNT version in TTF file')

        numTables = @data.readUint16()
        @data.skip 6 # We don't need the searchRange, entrySelector, or rangeShift (each 16 bits)

        # Add entries to tables object, indexing by their IDs
        for i in [ 0 .. numTables - 1 ]
            @tables[@data.readUint32()] = {
                checkSum: @data.readUint32()
                offset:   @data.readUint32()
                length:   @data.readUint32()
            }

        # Read individual tables
        this.readHeadTable()
        this.readGlyphs()
        this.readCmapTable()

    readHeadTable: ->
        headBuff = this.getTable TTF_HEAD
        if not headBuff
            throw new TTFException('Required head table not found in TTF file')

        @head.version = Utils.toFixed headBuff.readUint32()
        @head.fontRevision = Utils.toFixed headBuff.readUint32()
        @head.checkSumAdjustment = headBuff.readUint32()
        @head.magicNumber        = headBuff.readUint32()
        @head.flags              = headBuff.readUint16()
        @head.unitsPerEm         = headBuff.readUint16()

        # Skip the created and modified dates; not necessary,
        # and difficult to represent 64-bit ints in JS
        headBuff.skip 16

        @head.xMin   = headBuff.readUint16()
        @head.yMin   = headBuff.readUint16()
        @head.xMax   = headBuff.readUint16()
        @head.yMax   = headBuff.readUint16()

        macStyle = headBuff.readUint16()
        @head.bold   = !!(macStyle & FLAG_BIT_0)
        @head.italic = !!(macStyle & FLAG_BIT_1)

        @head.lowestRecPPEM     = headBuff.readUint16()
        @head.fontDirectionHint = headBuff.readInt16()
        @head.indexToLocFormat  = headBuff.readInt16()
        @head.glyphDataFormat   = headBuff.readInt16()

    readCmapTable: ->
        cmapTable = this.getTable TTF_CMAP
        if not cmapTable
            throw new TTFException('Required cmap table not found in TTF file')

        cmapTable.skip 2 # Skip table version number
        numEncTables = cmapTable.readUint16()
        encTables    = []

        for i in [ 0 ... numEncTables ]
            tableOffset  = cmapTable.offset
            platId       = cmapTable.readUint16()
            platEncoding = cmapTable.readUint16()
            offset       = cmapTable.readUint32()
            subtable     = cmapTable.slice tableOffset + offset

            encTables.push this.readCmapSubtable subtable

    readCmapSubtable: (buffer) ->
        format = buffer.readUint16()
        length = buffer.readUint16()

        switch format
            when 4
                

    readGlyphs: ->
        glyfTable  = this.getTable TTF_GLYF
        glyfOffset = glyfTable && @tables[TTF_GLYF].offset
        glyfLength = glyfTable && @tables[TTF_GLYF].length
        if not glyfTable
            throw new TTFException('Required glyf table not found in TTF file')

        while glyfTable.offset - glyfOffset < glyfLength
            @glyphs.push this.readGlyph(glyfTable)

    readGlyph: (buffer) ->
        glyph = {}

        glyph.numberOfContours = buffer.readInt16()
        glyph.xMin             = buffer.readInt16()
        glyph.yMin             = buffer.readInt16()
        glyph.xMax             = buffer.readInt16()
        glyph.yMax             = buffer.readInt16()

        if glyph.numberOfContours >= 0
            this.readSingleGlyph glyph, buffer
        else
            this.readCompoundGlyph glyph, buffer

        return glyph

    readSingleGlyph: (glyph, buffer) ->
        glyph.endpointIndexes = []
        glyph.points          = []

        for i in [0 .. glyph.numberOfContours - 1]
            glyph.endpointIndexes.push buffer.readUint16()

        # Get the number of points; this is possible because
        # the endpoints will always be indexes, and the last
        # endpoint for the last outline (contour) will be the
        # last point in the list.
        numberOfPoints = (Math.max glyph.endpointIndexes...) + 1 # (+1 as indexes begin at 0)

        # Skip the instructions
        buffer.skip buffer.readUint16()

        # End here if there are no contours
        if glyph.numberOfContours == 0
            return

        flags = []
        for i in [ 0 .. numberOfPoints - 1 ]
            flag = buffer.readUint8()
            flags.push flag
            glyph.points.push onCurve: (flag & FLAG_ON_CURVE > 0)

            # Check if flag is repeated; if it is, add that many /additional/
            # flags and points, and increment i accordingly (no. of flags <= no. of points)
            if flag & FLAG_REPEAT
                repeats = buffer.readUint8()
                i      += repeats 

                for [ 0 .. repeats - 1 ]
                    flags.push flag
                    glyph.points.push onCurve: (flag & FLAG_ON_CURVE > 0)

        # Process for reading coordinates is the same
        readCoords = (axis, byteFlag, sameFlag) ->

            # Value (the coordinate of this axis) changes relatively
            value     = 0

            for i in [ 0 .. numberOfPoints - 1 ]
                flag = flags[i]
                if flag & byteFlag
                    # Same flag here means positive value if set
                    value += (if flag & sameFlag then  1 else -1) * buffer.readUint8()
                else if flag & sameFlag == 0
                    # If not the same, read a 16-bit signed int
                    value += buffer.readInt16()

                points[i][axis] = value

        # Read x-coordinates
        readCoords 'x', FLAG_X_IS_BYTE, FLAG_X_IS_SAME
        readCoords 'y', FLAG_Y_IS_BYTE, FLAG_Y_IS_SAME

    readCompoundGlyph: (glyph, buffer) ->
        # TODO

    getTable: (name) ->
        if @tables.hasOwnProperty name
            offset = @tables[name].offset
            length = @tables[name].length

            # Return a new ByteBuffer of this table
            return @data.slice offset, offset + length

        null

window.addEventListener 'load', ->
    form = document.getElementById 'ttf-upload'
    form.addEventListener 'submit', (e) ->
        e.preventDefault()
        if e.target.ttf.files.length < 1
            alert 'Please upload a file!'

        file       = e.target.ttf.files[0]
        fileReader = new FileReader()
        fileReader.addEventListener 'load', ->
            buff     = fileReader.result
            fontBuff = ByteBuffer.wrap buff
            fontTag  = new DefineFont3Tag(fontBuff)
            console.log 'Success!'

        fileReader.readAsArrayBuffer(file)