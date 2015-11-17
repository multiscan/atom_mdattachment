# Nodejs packages
fs     = require 'fs'
md5    = require 'md5'
mkdirp = require 'mkdirp'
path   = require 'path'

# MdattachmentView = require './mdattachment-view'

{CompositeDisposable} = require 'atom'

supportedScopes = new Set ['source.gfm', 'text.plain.null-grammar']

# this is used to normalize attached files extensions
mime_to_ext = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/svg+xml': '.svg',
  'application/pdf': '.pdf'
}

module.exports = Mdattachment =
  subscriptions: null
  # mdattachmentView: null
  # modalPanel: null
  config:
    moveFiles:
      type: 'boolean'
      description: 'move dropped files instead of copying'
      default: false
    fileHashBytes:
      type: 'integer'
      description: 'How many bytes to use from input file to generate file name.'
      default: 1024
    oneDirFolAllBuffers:
      type: 'boolean'
      description: 'Use a single directory for storing all dropped files instead of creating a dedicated directory for each markdown file'
      default: false
    commonDirName:
      type: 'string'
      description: 'The name of the single directory for storing all dropped files when the above option is enabled'
      default: 'attachments'

  handleSubscription: (textEditor) ->
    if not supportedScopes.has textEditor.getRootScopeDescriptor().getScopesArray()[0]
      return
    textEditorElement = atom.views.getView textEditor
    textEditorElement.addEventListener 'drop', (e) => @handleDropEvent(textEditor, e)

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.observeTextEditors (textEditor) => @handleSubscription(textEditor)

  deactivate: ->
    # @modalPanel.destroy()
    @subscriptions.dispose()
    # @mdattachmentView.destroy()

  # serialize: ->
  #   # mdattachmentViewState: @mdattachmentView.serialize()
  #
  # toggle: ->
  #   console.log 'Mdattachment was toggled!'
  #
  #   # if @modalPanel.isVisible()
  #   #   @modalPanel.hide()
  #   # else
  #   #   @modalPanel.show()

  outDir: (textEditor) ->
    one = atom.config.get('mdattachment.oneDirFolAllBuffers')
    mdfile = path.parse(textEditor.getPath())
    if one
      atdir =  atom.config.get('mdattachment.commonDirName')
    else
      atdir = mdfile.base.replace(/\.[^.]*$/, '')
    odir = path.join mdfile.dir, atdir
    mkdirp.sync(odir) unless fs.existsSync(odir)
    is_dir = fs.statSync(odir).isDirectory()

    can_write = true
    try
      fs.accessSync odir, fs.W_OK|fs.X_OK
    catch
      can_write = false

    rodir = path.relative(mdfile.dir, odir)

    if is_dir && can_write
      return [odir, rodir]
    else
      raise "Problem setting up write directory"

  insertImage: (textEditor, src, desc) ->
    textEditor.insertText('!['+desc+'](' + src + ')\n')

  insertLink: (textEditor, src, desc) ->
    textEditor.insertText('['+desc+'](' + src + ')\n')

  insertCode: (textEditor, content, format) ->
    textEditor.insertText('```'+format+'\n' + content + '\n```')

  # compute hash of the file (only the first bytes are used)
  head_md5: (f) ->
    bc = atom.config.get('mdattachment.fileHashBytes')
    fd = fs.openSync f.path, 'r'
    buffer = new Buffer(bc)
    bc = fs.readSync fd, buffer, 0, bc, 0
    return md5 buffer

  # ------------------------------------------------------------ handleDropEvent
  # This is the main method
  handleDropEvent: (textEditor, e) ->
    files = e.dataTransfer.files
    move = atom.config.get('mdattachment.moveFiles')

    # TODO: write error message to GUI
    try
      [output_directory, relative_output_directory] = @outDir(textEditor)
    catch
      return

    for f in files


      fc = @classify_file(f)
      continue unless fc["class"]

      e.preventDefault?()
      e.stopPropagation?()

      if fc["class"] == "code"
        content = fs.readFileSync(f.path)
        @insertCode(textEditor, content, fc["format"])
      else
        # TODO: add option to preserve original filename
        out_f_name = @head_md5(f) + fc["ext"]
        out_f = path.join output_directory, out_f_name
        rel_out_f = path.join relative_output_directory, out_f_name

        # TODO: add option for deciding what to do if destination file already exists
        if move
          fs.renameSync f, out_f
        else
          fs.createReadStream(f.path).pipe(fs.createWriteStream(out_f))

        if fc["class"] == "image"
          @insertImage textEditor, rel_out_f, f.name
        else
          @insertLink textEditor, rel_out_f, f.name


  # -------------------------------------------------------------- classify_file
  classify_file: (f) ->
    mime = f.type
    fc={"class": null, "ext": null, "format": null, "fext": f.name.split('.').pop()}
    switch
      when mime.match "image/.*"
        fc["class"] = "image"
        fc["ext"]   = mime_to_ext[mime]
      when mime.match "application/pdf"
        fc["class"] = "link"
        fc["ext"]   = mime_to_ext[mime]
      when mime.match "text/x-shellscript"
        fc["class"] = "code"
        fc["format"] = "bash"
      when mime.match "text/x-perl"
        fc["class"] = "code"
        fc["format"] = "perl"
      when mime.match "text/x-awk"
        fc["class"] = "code"
        fc["format"] = "awk"
      when mime.match "text/x-python"
        fc["class"] = "code"
        fc["format"] = "python"
      # sometime mime is just text/plain. In this case we use file extension
      # TODO: find a more clever way of doing this (there should be no need to add by hand every single language!)
      when mime.match "text/"
        fc["class"] = "code"
        ext = fc["fext"]
        fc["format"] = switch ext
          when "rb" then "ruby"
          when "sh" then "bash"
          when "py" then "python"
          when "awk" then "awk"
          when "pl" then "perl"
          when "c" then "c"
          when "c++" then "c"
          when "js" then "javascript"
          else ""
    return fc
