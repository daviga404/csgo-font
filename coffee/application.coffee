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
    # @param {ByteBuffer} ttfBuffer  Buffer of TTF data
    # @param {Number}     fileOffset The current offset of the SWF file
    # @throws {TTFException} If the TTF file was invalid
    ###
    constructor: (ttfBuffer, fileOffset) ->
        super 75 # Tag type = 75

        reader = new TTFReader(ttfBuffer)
        reader.read()

        # Get and ensure the necessary tables exist in the file
        head = (reader.getTable TTF_HEAD) or throw new TTFException('Head table not found')
        hhea = (reader.getTable TTF_HHEA) or throw new TTFException('Horizontal header table not found')

        # Skip table version, font revision, checksum, and magic number
        head.skip 16 

        flags = head.readUint16() # We may need this in the future!
        units = head.readUint16() # Units per EM square




        ###
        # Ensure hhea table exists
        if not (hhea = reader.getTable TTF_HHEA)
            throw new TTFException('Horizontal header table not found; invalid TTF file?')

        if Utils.toFixed hhea.readUint32() is not 1.0
            throw new TTFException('Invalid SFNT version in TTF file')
        ###


class TTFException extends Error
    constructor: (@message) ->
        @name = 'TTFException'

class TTFReader

    # Constants
    TTF_HHEA = 0x68686561 # Horizontal header table
    TTF_HEAD = 0x68656164 # Head table
    TTF_GLYF = 0x676C7966 # Glyf (glyph) table

    FLAG_BIT_0 = 0x1 # Bitmask for bit 0 of flags
    FLAG_BIT_1 = 0x2 # Bitmask for bit 1 of flags

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

        # Read the 'head' table and store values
        this.readHeadTable()
        this.readGlyphs()

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

        for i in [0 .. glyph.numberOfContours - 1]
            glyph.endpointIndexes.push buffer.readUint16()

        # Get the number of points; this is possible because
        # the endpoints will always be indexes, and the last
        # endpoint for the last outline (contour) will be the
        # last point in the list.
        numberOfPoints = Math.max glyph.endpointIndexes...

        # Skip the instructions
        buffer.skip buffer.readUint16()

        # End here if there are no contours
        if glyph.numberOfContours == 0
            return

    readCompoundGlyph: (glyph, buffer) ->


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