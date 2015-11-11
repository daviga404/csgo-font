ByteBuffer = dcodeIO.ByteBuffer
Utils      =
    # Pads a number (in string form) to `len` digits.
    pad: (str, len) -> (Array(len - str.length + 1).join '0') + str

    # Converts a 32 bit int into a fixed point number (16.16)
    toFixed: (num) -> (num >> 16) + (num & 0xFFFF) * Math.pow(2, -16)

    toF2Dot14: (num) -> (num >> 14) + (num & 0x3FFF) * Math.pow(2, -14)

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
            0# TODO
        )

        console.log reader.encodingTables

class TTFException extends Error
    constructor: (@message) ->
        @name = 'TTFException'

class TTFReader

    # Constants
    TTF_HHEA = 0x68686561 # Horizontal header table
    TTF_HEAD = 0x68656164 # Head table
    TTF_GLYF = 0x676C7966 # Glyf (glyph) table
    TTF_CMAP = 0x636D6170 # Cmap (character mapping) table
    TTF_LOCA = 0x6C6F6361 # Loca (glyph location) table
    TTF_MAXP = 0x6D617870 # Maxp (maximum profile) table

    # Bitmask constants
    FLAG_BIT_0 = 0x1
    FLAG_BIT_1 = 0x2
    FLAG_BIT_2 = 0x4
    FLAG_BIT_3 = 0x8
    FLAG_BIT_4 = 0x10
    FLAG_BIT_5 = 0x20
    FLAG_BIT_6 = 0x40
    FLAG_BIT_7 = 0x80
    FLAG_BIT_8 = 0x100
    FLAG_BIT_9 = 0x200

    # Single glyph flags
    FLAG_ON_CURVE  = FLAG_BIT_0
    FLAG_X_IS_BYTE = FLAG_BIT_1
    FLAG_Y_IS_BYTE = FLAG_BIT_2
    FLAG_REPEAT    = FLAG_BIT_3
    FLAG_X_IS_SAME = FLAG_BIT_4
    FLAG_Y_IS_SAME = FLAG_BIT_5

    # Compound glyph flags
    FLAG_ARG_1_AND_2_ARE_WORDS = FLAG_BIT_0
    FLAG_ARGS_ARE_XY_VALUES    = FLAG_BIT_1
    FLAG_ROUND_XY_TO_GRID      = FLAG_BIT_2
    FLAG_WE_HAVE_A_SCALE       = FLAG_BIT_3 # Bit 4 is reserved
    FLAG_MORE_COMPONENTS       = FLAG_BIT_5
    FLAG_WE_HAVE_AN_XY_SCALE   = FLAG_BIT_6
    FLAG_WE_HAVE_A_TWO_BY_TWO  = FLAG_BIT_7
    FLAG_WE_HAVE_INSTRUCTIONS  = FLAG_BIT_8
    FLAG_USE_MY_METRICS        = FLAG_BIT_9

    # Index to Loc Format
    FORMAT_SHORT = 0
    FORMAT_LONG  = 1

    # Glyph types
    GLYPH_TYPE_SINGLE   = 'single'
    GLYPH_TYPE_COMPOUND = 'compound'

    constructor: (data) ->
        @data   = data.clone() # ByteBuffer of the raw TTF data
        @tables = {}           # Tables in file, indexed by their IDs
        @info   = {}           # Head & maxp information in TTF; keys are the relevant table (e.g. 'maxp'), and keys of those objects correspond to their camelCase equivalent in the TTF specification
        @glyphs = []           # Array of glyphs in the TTF file [TODO]
        @encodingTables = []   # Array of char -> glyph mappings for different encodings. Contains objects with platformId, platformEncoding, and glyphIndexes keys

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
        this.readInfo()
        this.readGlyphs()
        this.readCmapTable()

    readInfo: ->

        ###
        # Read 'head' table
        ###
        headBuff = this.getTable TTF_HEAD
        if not headBuff
            throw new TTFException('Required head table not found in TTF file')

        @info.head = {}
        @info.head.version = Utils.toFixed headBuff.readUint32()
        @info.head.fontRevision = Utils.toFixed headBuff.readUint32()
        @info.head.checkSumAdjustment = headBuff.readUint32()
        @info.head.magicNumber        = headBuff.readUint32()
        @info.head.flags              = headBuff.readUint16()
        @info.head.unitsPerEm         = headBuff.readUint16()

        # Skip the created and modified dates; not necessary,
        # and difficult to represent 64-bit ints in JS
        headBuff.skip 16

        @info.head.xMin   = headBuff.readUint16()
        @info.head.yMin   = headBuff.readUint16()
        @info.head.xMax   = headBuff.readUint16()
        @info.head.yMax   = headBuff.readUint16()

        macStyle = headBuff.readUint16()
        @info.head.bold   = !!(macStyle & FLAG_BIT_0)
        @info.head.italic = !!(macStyle & FLAG_BIT_1)

        @info.head.lowestRecPPEM     = headBuff.readUint16()
        @info.head.fontDirectionHint = headBuff.readInt16()
        @info.head.indexToLocFormat  = headBuff.readInt16()
        @info.head.glyphDataFormat   = headBuff.readInt16()

        ###
        # Read 'maxp' table
        ###
        maxpBuff = this.getTable TTF_MAXP
        if not maxpBuff
            throw new TTFException('Required maxp table not found in TTF file')

        maxpBuff.skip 4
        @info.maxp = {}
        @info.maxp.numGlyphs             = maxpBuff.readUint16()
        @info.maxp.maxPoints             = maxpBuff.readUint16()
        @info.maxp.maxContours           = maxpBuff.readUint16()
        @info.maxp.maxCompositePoints    = maxpBuff.readUint16()
        @info.maxp.maxCompositeContours  = maxpBuff.readUint16()
        @info.maxp.maxZones              = maxpBuff.readUint16()
        @info.maxp.maxTwilightPoints     = maxpBuff.readUint16()
        @info.maxp.maxStorage            = maxpBuff.readUint16()
        @info.maxp.maxFunctionDefs       = maxpBuff.readUint16()
        @info.maxp.maxInstructionDefs    = maxpBuff.readUint16()
        @info.maxp.maxStackElements      = maxpBuff.readUint16()
        @info.maxp.maxSizeOfInstructions = maxpBuff.readUint16()
        @info.maxp.maxComponentElements  = maxpBuff.readUint16()
        @info.maxp.maxComponentDepth     = maxpBuff.readUint16()

    readCmapTable: ->
        cmapTable = this.getTable TTF_CMAP
        if not cmapTable
            throw new TTFException('Required cmap table not found in TTF file')

        tableStart   = cmapTable.offset
        cmapTable.skip 2 # Skip table version number
        numEncTables = cmapTable.readUint16()
        encTables    = []

        for i in [ 0 ... numEncTables ]
            platId       = cmapTable.readUint16()
            platEncoding = cmapTable.readUint16()
            offset       = cmapTable.readUint32()
            subtable     = cmapTable.slice tableStart + offset

            encTables.push
                platformId: platId,
                platformEncoding: platEncoding,
                glyphIndexes: this.readCmapSubtable subtable

        @encodingTables = encTables

    readCmapSubtable: (buffer) ->
        format       = buffer.readUint16()
        length       = buffer.readUint16()
        #glyphIndexes = []

        switch format

            # Format 4 : Microsoft's Format
            when 4
                return this.processCmapFormat4 buffer

            else
                return []
                        
    processCmapFormat4: (buffer) ->

        glyphIndexes = []
        segments     = []

        buffer.skip 2 # Skip version
        segCount = buffer.readUint16() / 2  # segCountX2
        buffer.skip 6 # Skip search optimization

        # Read endCodes
        for i in [ 0 ... segCount ]
            segments.push endCode: buffer.readUint16()

        buffer.skip 2 # Skip reserved

        # Read startCodes
        for i in [ 0 ... segCount ]
            segments[i].startCode = buffer.readUint16()

        # Read idDeltas
        for i in [ 0 ... segCount ]
            segments[i].idDelta = buffer.readUint16()

        # Get glyph to char mappings
        for i in [ 0 ... segCount ] 
            offset = buffer.offset
            segments[i].idRangeOffset = buffer.readUint16()

            # If idRangeOffset is 0, the glyph index of this character
            # is (code + idDelta) mod 65536
            if segments[i].idRangeOffset == 0
                for j in [ segments[i].startCode .. segments[i].endCode ]
                    glyphIndexes[j] = (j + segments[i].idDelta) % 65536

            # If idRangeOffset is non-zero, it is used as an offset into
            # the following glyphIdArray. Consult TTF documentation for how 
            # the offset for this index is calculated.
            else
                for j in [ segments[i].startCode .. segments[i].endCode ]
                    glyphIndexes[j] = buffer.readUint16 (offset + 2 * (j - segments[i].startCode))

        return glyphIndexes

    readGlyphs: ->
        # Read 'loca' table to find out offsets of glyphs
        locaTable = this.getTable TTF_LOCA
        if not locaTable
            throw new TTFException('Required loca table not found in TTF file')

        offsets    = []
        readOffset = if @info.head.indexToLocFormat == FORMAT_SHORT then ByteBuffer.prototype.readUint16 else ByteBuffer.prototype.readUint32
        multiplier = if @info.head.indexToLocFormat == FORMAT_SHORT then 2 else 1
        for i in [ 0 .. @info.maxp.numGlyphs ] # Goes to maxp.numGlyphs + 1
            offsets.push readOffset.apply(locaTable) * multiplier

        # Read glyph table
        glyfTable  = this.getTable TTF_GLYF
        if not glyfTable
            throw new TTFException('Required glyf table not found in TTF file')

        for i in [ 0 ... @info.maxp.numGlyphs ]
            offset = (glyfTable.offset + offsets[i]) # Offsets are relative to start of file (for whatever reason...)
            @glyphs.push this.readGlyph glyfTable.slice offset

    readGlyph: (buffer) ->
        glyph = {}

        glyph.numberOfContours = buffer.readInt16()
        glyph.xMin             = buffer.readInt16()
        glyph.yMin             = buffer.readInt16()
        glyph.xMax             = buffer.readInt16()
        glyph.yMax             = buffer.readInt16()

        if glyph.numberOfContours >= 0
            this.readSingleGlyph glyph, buffer
        else if glyph.numberOfContours == -1
            this.readCompoundGlyph glyph, buffer
        else
            throw new TTFException('Invalid number of contours while reading glyph')

        return glyph

    readSingleGlyph: (glyph, buffer) ->
        glyph.type = GLYPH_TYPE_SINGLE
        glyph.endpointIndexes = []
        glyph.points          = []

        for i in [0 ... glyph.numberOfContours]
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
        i = 0
        while i < numberOfPoints
            flag = buffer.readUint8()
            flags.push flag
            glyph.points.push onCurve: (flag & FLAG_ON_CURVE > 0)

            # Check if flag is repeated; if it is, add that many /additional/
            # flags and points, and increment i accordingly (no. of flags <= no. of points)
            if flag & FLAG_REPEAT
                repeats = buffer.readUint8()
                i      += repeats

                for [ 0 ... repeats ]
                    flags.push flag
                    glyph.points.push onCurve: (flag & FLAG_ON_CURVE > 0)

            i++

        # Process for reading coordinates is the same
        readCoords = (axis, byteFlag, sameFlag) ->

            # Value (the coordinate of this axis) changes relatively
            value     = 0

            for i in [ 0 ... glyph.points.length ]
                flag = flags[i]
                if flag & byteFlag
                    # Same flag here means positive value if set
                    value += (if flag & sameFlag then 1 else -1) * buffer.readUint8()
                else if (~flag) & sameFlag
                    # If not the same, read a 16-bit signed int
                    value += buffer.readInt16()

                glyph.points[i][axis] = value

        # Read x-coordinates
        readCoords 'x', FLAG_X_IS_BYTE, FLAG_X_IS_SAME
        readCoords 'y', FLAG_Y_IS_BYTE, FLAG_Y_IS_SAME

    readCompoundGlyph: (glyph, buffer) ->
        glyph.type       = GLYPH_TYPE_COMPOUND
        glyph.components = []
        flags            = 0

        # Do until no longer more components
        while true
            component =
                flags:      buffer.readUint16()
                glyphIndex: buffer.readUint16()
                matrix:     a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 # Set up as identity matrix

            # Assign flags = component.flags for convenience (and use outside of loop)
            flags = component.flags

            # Read arguments of appropriate size
            argument1  = if flags & FLAG_ARG_1_AND_2_ARE_WORDS then buffer.readUint16() else buffer.readUint8()
            argument2  = if flags & FLAG_ARG_1_AND_2_ARE_WORDS then buffer.readUint16() else buffer.readUint8()

            # Flags are X/Y offsets
            if flags & FLAG_ARGS_ARE_XY_VALUES
                component.matrix.e = argument1
                component.matrix.f = argument2
            # Flags are glyph point indexes to overlay
            else
                component.srcPoint = argument1
                component.dstPoint = argument2 

            # Read scales (if necessary) into matrix
            if flags & FLAG_WE_HAVE_A_SCALE
                component.matrix.a = Utils.toF2Dot14 buffer.readUint16()
                component.matrix.d = component.matrix.d
            else if flags & FLAG_WE_HAVE_AN_XY_SCALE
                component.matrix.a = Utils.toF2Dot14 buffer.readUint16()
                component.matrix.d = Utils.toF2Dot14 buffer.readUint16()
            else if flags & FLAG_WE_HAVE_A_TWO_BY_TWO
                component.matrix.a = Utils.toF2Dot14 buffer.readUint16()
                component.matrix.b = Utils.toF2Dot14 buffer.readUint16()
                component.matrix.c = Utils.toF2Dot14 buffer.readUint16()
                component.matrix.d = Utils.toF2Dot14 buffer.readUint16()

            glyph.components.push component

            break unless flags & FLAG_MORE_COMPONENTS

        # Skip instructions
        if flags & FLAG_WE_HAVE_INSTRUCTIONS
            buffer.skip buffer.readUint16()

    # TODO doc
    getTable: (name) ->
        if @tables.hasOwnProperty name
            offset = @tables[name].offset
            length = @tables[name].length

            # Return a new ByteBuffer of this table
            return @data.slice offset, offset + length

        null

    ###
    # Gets loaded information about the font. The data is returned
    # as an object, indexed by keys of the tables (e.g. 'head', 'maxp').
    # The values of these keys are also objects, with keys as their
    # camelCase equivalents to those in the TTF specification.
    #
    # Currently, the tables loaded in font info are 'head', and 'maxp'
    #
    # @return {Object}
    ####
    getFontInfo: ->
        @info

    # TODO doc
    getGlyphs: ->
        @glyphs

    getGlyph: (charId) ->
        # TODO
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

            ttfReader = new TTFReader(fontBuff)
            ttfReader.read()

            console.log 'Trying to do A character...'
            glyphIndex = -1

            for table in ttfReader.encodingTables
                # MS Unicode
                if table.platformId == 3 and table.platformEncoding == 1

                    for key in table.glyphIndexes
                        if table.glyphIndexes[key] == 0
                            console.log key

                    if 65 in table.glyphIndexes
                        glyphIndex = table.glyphIndexes[65]

            console.log glyphIndex
            console.log ttfReader.getGlyphs()

            #fontTag  = new DefineFont3Tag(fontBuff, { fontId: 4 })
            console.log 'Success!'

        fileReader.readAsArrayBuffer(file)