# Nodejs packages
fs     = require 'fs'
md5    = require 'md5'
mkdirp = require 'mkdirp'
path   = require 'path'

# MdattachmentView = require './mdattachment-view'

{CompositeDisposable} = require 'atom'

supportedScopes = new Set ['source.gfm', 'text.plain.null-grammar']

mime_to_ext = {
  'image/png': '.png',
  'image/jpeg': '.jpg'
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

  # ------------------------------------------------------------ Package methods

  outDir: (textEditor) ->
    one = atom.config.get('mdattachment.oneDirFolAllBuffers')
    mdfile = path.parse(textEditor.getPath())
    if one
      atdir =  atom.config.get('mdattachment.commonDirName')
    else
      atdir = mdfile.base.replace(/\.[^.]*$/, '')
    odir = path.join mdfile.dir, atdir
    console.log "odir should be " + odir
    mkdirp.sync(odir) unless fs.existsSync(odir)
    is_dir = fs.statSync(odir).isDirectory()

    can_write = true
    try
      fs.accessSync odir, fs.W_OK|fs.X_OK
    catch
      can_write = false

    rodir = path.relative(mdfile.dir, odir)
    console.log "odir = " + odir + "    rodir = " + rodir

    if is_dir && can_write
      return [odir, rodir]
    else
      raise "Problem setting up write directory"

  insertImage: (textEditor, src) ->
    textEditor.insertText('![](' + src + ')\n')

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
      # TODO: add error message
      continue unless f.type.match "image/.*"
      do (f) =>
        console.log 'Mdattachment got file ' + f.path + ' dropped. type=' + f.type
        e.preventDefault?()
        e.stopPropagation?()

        fd = fs.openSync f.path, 'r'
        buffer = new Buffer(1024)
        num = fs.readSync fd, buffer, 0, 1024, 0
        key = md5 buffer
        ext = mime_to_ext[f.type]
        out_f = path.join output_directory, key+ext
        rel_out_f = path.join relative_output_directory, key+ext
        console.log "Key for " + f.path + " = " + key + "  ext = " + ext + "   num = " + num

        # TODO: add option for deciding what to do if destination file already exists
        if move
          fs.renameSync f, out_f
        else
          fs.createReadStream(f.path).pipe(fs.createWriteStream(out_f))

        console.log "f.type="+f.type+"     match?" + f.type.match("image/.*")
        switch
          when f.type.match("image\/.*") then @insertImage textEditor, rel_out_f
          else return
