" -*- vim -*-
" FILE: mib_translator.vim
" PLUGINTYPE: plugin
" DESCRIPTION: Translates SNMP OIDs from within Vim.
" HOMEPAGE: https://github.com/caglartoklu/mib_translator.vim
" LICENSE: https://github.com/caglartoklu/mib_translator.vim/blob/master/LICENSE
" AUTHOR: caglartoklu

if exists("g:loaded_mib_translator") || &cp
    " If it already loaded, do not load it again.
    finish
endif
let g:loaded_mib_translator = 1


function! s:SetDefaultSettings()
    " Reads the settings, if they are not defined,
    " it defines them with default settings.
    if exists('g:OidTranslatorBufferName') == 0
        " The name of the buffer to be used to display the
        " result of the translation process.
        " It is not recommended to change this value since
        " it can cause buffer name clashes.
        let g:OidTranslatorBufferName = 'OIDTranslator'
    endif

    if exists('g:OidTranslatorBufferSize') == 0
        " The visible line count of the translation buffer.
        " If it is not convenient for you, change it
        " from within VIMRC by copying the following line.
        let g:OidTranslatorBufferSize = 10
    endif

    if exists('g:OidTranslatorSnmpTranslatePath') == 0
        " The path to the snmptranslate executable of Net-SNMP.
        let g:OidTranslatorSnmpTranslatePath = 'snmptranslate'
    endif

    if exists('g:OidTranslatorNetSnmpLogging') == 0
        " Whether the logs from Net-SNMP to be displayed in
        " translation window or not.
        let g:OidTranslatorNetSnmpLogging = 0
    endif

    if exists('g:OidTranslatorExposingCommand') == 0
        " Prints the command sent to Net-SNMP
        " as first line in the translation buffer.
        let g:OidTranslatorExposingCommand = 1
    endif

    if exists('g:OidTranslatorInferMapping') == 1
        " Defines a customizable key binding to inference.
        " Example for VIMRC:
        " let g:OidTranslatorInferMapping = '<leader>mb'
        let cmd = 'map ' . g:OidTranslatorInferMapping . ' :OidTranslateInfer<cr>'
        exec cmd
    endif
endfunction


function! s:GetOidTranslatorBufferNumber()
    " Returns the buffer number of the OID Translator.
    " It can also be used to check if the buffer exists
    " or not. If this function returns -1, it means that
    " the buffer does not exist.
    return bufnr(g:OidTranslatorBufferName)
endfunction


function! s:CreateOidTranslatorBuffer()
    " Creates the OID Tranlator buffer.
    " The buffer must be deleted by calling
    " DeleteOidTranslatorBuffer() before this function.
    call s:CreateBuffer(g:OidTranslatorBufferName, g:OidTranslatorBufferSize)
endfunction


function! s:DeleteOidTranslatorBuffer()
    " If the OID Translator buffer exists, this function deletes it.
    " It has no effect otherwise.
    let OidTranslatorBufferNumber = s:GetOidTranslatorBufferNumber()
    if OidTranslatorBufferNumber != -1
        " If the buffer exists, deletes it.
        " If the buffer is deleted manually using ':bd', the following
        " exec used to raise an error earlier.
        " Now launched with 'silent!' to fix that.
        " exec 'bdelete ' . g:OidTranslatorBufferName
        silent! exec 'bdelete ' . g:OidTranslatorBufferName
        setlocal modifiable
    endif
endfunction


function! s:CreateBuffer(bufferName, splitSize)
    " Creates the specified buffer name with the specified split size.
    " This is a more generic function and can be used for
    " other scripts too.

    let finalBufferName = a:bufferName
    exec a:splitSize . 'new "' . finalBufferName . '"'
    exec 'edit ' . finalBufferName

    " Make the buffer writable.
    setlocal modifiable

    " Keep the window width when windows are opened or closed.
    " setlocal winfixwidth

    " Do not use a swapfile for the buffer.
    setlocal noswapfile

    " Buffer not related to a file and will not be written.
    setlocal buftype=nofile

    " When off, lines will not wrap and only part of long lines
    " will be displayed.
    setlocal nowrap

    " When non-zero, a column with the specified width is shown at the side
    " of the window which indicates open and closed folds.
    setlocal foldcolumn=0

    " When this option is set, the buffer shows up in the buffer list.
    " setlocal nobuflisted

    " When on spell checking will be done.
    setlocal nospell

    " Do not print the line number in front of each line.
    setlocal nonumber

    " Remove all abbreviations for Insert mode
    iabc <buffer>

    " Highlight the screen line of the cursor with CursorLine.
    setlocal cursorline

    setlocal number
endfunction


function! s:ExtractOidFromLine(current_line, current_col)
    " If the cursor is placed on an OID such as .1.3.6.1.2.1.55
    " this function returns the full OID.
    " <cword> is not adequate for the task at the hand,
    " since it will return a single number.
    " This function goes left and right in the line
    " to extract the OID.
    let result = ''
    " An OID number to test: .1.3.6.1.2.1.55 Yes, it is an OID.

    " Get the characters at right.
    for i in range(a:current_col, strlen(a:current_line))
        let ch = a:current_line[i]
        if stridx('0123456789.', ch) > -1
            let result = result . ch
        else
            break
        endif
    endfor

    " Go to left, get characters at left.
    let first_part = strpart(a:current_line, 0, a:current_col)
    let char_range = reverse(range(0, a:current_col-1))
    for i in char_range
        let ch = a:current_line[i]
        if stridx('0123456789.', ch) > -1
            let result = ch . result
        else
            break
        endif
    endfor

    return result
endfunction


function! s:cleanOid(oidNumber)
    " If the OID starts with '1.1' such as '1.1.3.6', then
    " remove the leading '1' so it becomes '.1.3.6'.
    " This is beccause Net-SNMP's snmptranslate can not
    " translate OIDs starting with '1.1'.
    let oidNumber2 = a:oidNumber
    if oidNumber2[:2] == '1.1'
        let oidNumber2 = oidNumber2[1:]
    endif
    return oidNumber2
endfunction


function! s:OidTranslateFromOid(oidNumber)
    " Translates the given SNMP OID.
    " This is the forward translation, the OID information
    " is found from the OID number.
    "
    " The oidNumber is a string like '.1.3.6.1.2.1.55'.
    "
    " This function uses 'snmptranslate' command of Net-SNMP,
    " and returns extracts detailed information.

    if len(a:oidNumber) > 0
        " If there is a parameter, directly use that.
        let oidNumber2 = a:oidNumber
    else
        " If there is no parameter, just use the current word.
        " Since OID is a number with digits and dots, just getting the
        " current word as done in getting a label will not do.
        " So, we need to go hard way to get the OID.
        let current_line = getline('.')
        let current_col = virtcol('.')
        let oidNumber2 = s:ExtractOidFromLine(current_line, current_col)
    endif

    " if the OID starts with '1.1.3', then it is impossible for
    " Net-SNMP to translate it. So, remove the starting '1'.
    let oidNumber2 = s:cleanOid(oidNumber2)

    if len(oidNumber2) > 0
        " -m ALL : Uses all MIB files.
        " -On    : Prints OIDs numerically.
        " -Td    : Prints full details of the given OID.
        let parameters = '-m ALL -On -Td'
        if g:OidTranslatorNetSnmpLogging == 0
            let parameters = parameters . ' -Ln'
        endif
        let cmd = g:OidTranslatorSnmpTranslatePath . ' ' . parameters . ' ' . oidNumber2

        call s:DeleteOidTranslatorBuffer()
        call s:CreateOidTranslatorBuffer()
        " At this point, we have a buffer for sure.

        " Focus the OID Translator buffer.
        exec 'edit ' . g:OidTranslatorBufferName

        " We do not want to see the process returned number,
        " so we are using silent!.
        silent! exec 'read ! ' . cmd
        if g:OidTranslatorExposingCommand == 1
            call setline(1, cmd)
        endif

        call s:DoPostOperations()
    else
        echo "You have to provide or locate an OID label."
    endif
endfunction


function! s:OidTranslateFromLabel(oidLabel)
    " Reverse translates the given OID label.
    " This is the reverse translation, the OID information
    " is found from the OID label.
    "
    " The oidLabel is a string like 'ipv6MIB'.
    "
    " This function uses 'snmptranslate' command of Net-SNMP,
    " and returns extracted detailed information.

    if len(a:oidLabel) > 0
        " If there is a parameter, directly use that.
        let oidLabel2 = a:oidLabel
    else
        " If there is no parameter, just use the current word.
        let oidLabel2 = expand('<cword>')
    endif

    if len(oidLabel2) > 0
        " -m ALL : Uses all MIB files.
        " -IR    : Uses random access to OID labels.
        " -On    : Prints OIDs numerically.
        " -Td    : Prints full details of the given OID.
        let parameters = '-m ALL -IR -On -Td'
        if g:OidTranslatorNetSnmpLogging == 0
            let parameters = parameters . ' -Ln'
        endif
        let cmd = g:OidTranslatorSnmpTranslatePath . ' ' . parameters . ' ' . oidLabel2

        call s:DeleteOidTranslatorBuffer()
        call s:CreateOidTranslatorBuffer()
        " At this point, we have a buffer for sure.

        " Focus the OID Translator buffer.
        exec 'edit ' . g:OidTranslatorBufferName

        " We do not want to see the process returned number,
        " so we are using silent!.
        silent! exec 'read ! ' . cmd
        if g:OidTranslatorExposingCommand == 1
            call setline(1, cmd)
        endif

        call s:DoPostOperations()
    else
        echo "You have to provide or locate an OID label."
    endif
endfunction


function! s:OidTranslateInfer()
    " Checks the cursor position, and tries to infer the type,
    " and calls the appropriate function, OidTranslateFromOid
    " or OidTranslateFromLabel.
    " This function takes no parameter, it just uses the cursor position.
    let current_line = getline('.')
    let current_col = virtcol('.')
    let under_cursor = s:ExtractOidFromLine(current_line, current_col)
    if strlen(under_cursor) > 1
        call s:OidTranslateFromOid(under_cursor)
    else
        " No OID could be collected, only a single digit, or a dot.
        " This is supposed to be a label.
        call s:OidTranslateFromLabel('')
    endif
endfunction


function! s:OidTranslateNumberList()
    " Displays all the OID numbers in a separate buffer.
    " -m ALL : Uses all MIB files.
    " -To    : enable OID report.
    let parameters = '-m ALL -To'
    if g:OidTranslatorNetSnmpLogging == 0
        let parameters = parameters . ' -Ln'
    endif
    let cmd = g:OidTranslatorSnmpTranslatePath . ' ' . parameters

    call s:DeleteOidTranslatorBuffer()
    call s:CreateOidTranslatorBuffer()
    " At this point, we have a buffer for sure.

    " Focus the OID Translator buffer.
    exec 'edit ' . g:OidTranslatorBufferName

    " We do not want to see the process returned number,
    " so we are using silent!.
    silent! exec 'read !' . cmd
    if g:OidTranslatorExposingCommand == 1
        call setline(1, cmd)
    endif

    call s:DoPostOperations()
endfunction


function! s:DoPostOperations()
    " This function is called at the end of OidTranslateFromOid() and
    " OidTranslateFromLabel().

    " What is seen is a part of a MIB file, paint it with its syntax colors.
    exec "set filetype=mib"

    " When off the buffer contents cannot be changed.
    setlocal nomodifiable
endfunction


" Set the settings once.
call s:SetDefaultSettings()


" Define commands to use.
command! -nargs=? OidTranslateFromOid : call s:OidTranslateFromOid(<q-args>)
command! -nargs=? OidTranslateFromLabel : call s:OidTranslateFromLabel(<q-args>)
command! -nargs=0 OidTranslateNumberList : call s:OidTranslateNumberList()
command! -nargs=0 OidTranslateInfer : call s:OidTranslateInfer()
