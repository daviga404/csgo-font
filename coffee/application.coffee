ByteBuffer = dcodeIO.ByteBuffer

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
        idAndLength  = (@id & 0x3FF) << 6                                       # 10 bits; shift left to align with uint16
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
        pad       = (str, len) -> (Array(len - str.length + 1).join '0') + str
        bitString = ""
        bits      = (Math.max (coord.toString(2).length for coord in rect)...) # Get the maximum bit length

        # Append bit length to the bitString
        bitString += pad bits.toString(2), 5

        # Append each coord [in order], padding to `bits` bit
        for i in [0..3]
            bitString += pad rect[i].toString(2).replace(/[^0-9]/g, ''), bits

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

    ###*
    # Constructs a new DefineFont3 tag. This should
    # be instantiated with a ByteBuffer, `ttfBuffer`,
    # that contains the TTF data for this font tag.
    #
    # @param {ByteBuffer} ttfBuffer Buffer of TTF data
    ###
    constructor: (ttfBuffer) ->
        super 75 # Tag type = 75