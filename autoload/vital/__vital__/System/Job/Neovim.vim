" http://vim-jp.org/blog/2016/03/23/take-care-of-patch-1577.html
function! s:is_available() abort
  return has('nvim') && has('nvim-0.2.0')
endfunction

function! s:start(args, options) abort
  let job = extend(copy(s:job), a:options)
  let job_options = {}
  if has_key(a:options, 'cwd')
    let job_options.cwd = a:options.cwd
  endif
  if has_key(job, 'on_stdout')
    let job_options.on_stdout = funcref('s:_on_stdout', [job])
  endif
  if has_key(job, 'on_stderr')
    let job_options.on_stderr = funcref('s:_on_stderr', [job])
  endif
  if has_key(job, 'on_exit')
    let job_options.on_exit = funcref('s:_on_exit', [job])
  else
    let job_options.on_exit = funcref('s:_on_exit_raw', [job])
  endif
  let job.__job = jobstart(a:args, job_options)
  let job.__exitval = v:null
  let job.args = a:args
  return job
endfunction

function! s:_on_stdout(job, job_id, data, event) abort
  call a:job.on_stdout(a:data)
endfunction

function! s:_on_stderr(job, job_id, data, event) abort
  call a:job.on_stderr(a:data)
endfunction

function! s:_on_exit(job, job_id, exitval, event) abort
  let a:job.__exitval = a:exitval
  call a:job.on_exit(a:exitval)
endfunction

function! s:_on_exit_raw(job, job_id, exitval, event) abort
  let a:job.__exitval = a:exitval
endfunction

" Instance -------------------------------------------------------------------
function! s:_job_id() abort dict
  if &verbose
    echohl WarningMsg
    echo 'vital: System.Job: job.id() is deprecated. Use job.pid() instead.'
    echohl None
  endif
  return self.pid()
endfunction

function! s:_job_pid() abort dict
  return jobpid(self.__job)
endfunction

function! s:_job_status() abort dict
  try
    sleep 1m
    call jobpid(self.__job)
    return 'run'
  catch /^Vim\%((\a\+)\)\=:E900/
    return 'dead'
  endtry
endfunction

if exists('*chansend') " Neovim 0.2.3
  function! s:_job_send(data) abort dict
    return chansend(self.__job, a:data)
  endfunction
else
  function! s:_job_send(data) abort dict
    return jobsend(self.__job, a:data)
  endfunction
endif

if exists('*chanclose') " Neovim 0.2.3
  function! s:_job_close() abort dict
    call chanclose(self.__job, 'stdin')
  endfunction
else
  function! s:_job_close() abort dict
    call jobclose(self.__job, 'stdin')
  endfunction
endif

function! s:_job_stop() abort dict
  try
    call jobstop(self.__job)
  catch /^Vim\%((\a\+)\)\=:E900/
    " NOTE:
    " Vim does not raise exception even the job has already closed so fail
    " silently for 'E900: Invalid job id' exception
  endtry
endfunction

function! s:_job_wait(...) abort dict
  let timeout = a:0 ? a:1 : v:null
  let exitval = timeout is# v:null
        \ ? jobwait([self.__job])[0]
        \ : jobwait([self.__job], timeout)[0]
  if exitval != -3
    return exitval
  endif
  " Wait until 'on_exit' callback is called
  while self.__exitval is# v:null
    sleep 1m
  endwhile
  return self.__exitval
endfunction

" To make debug easier, use funcref instead.
let s:job = {
      \ 'id': funcref('s:_job_id'),
      \ 'pid': funcref('s:_job_pid'),
      \ 'status': funcref('s:_job_status'),
      \ 'send': funcref('s:_job_send'),
      \ 'close': funcref('s:_job_close'),
      \ 'stop': funcref('s:_job_stop'),
      \ 'wait': funcref('s:_job_wait'),
      \}
