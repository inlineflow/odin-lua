package luatry

import "core:fmt"
import lua "vendor:lua/5.1"
import "core:c"
import "base:runtime"
import "core:strings"
import os "core:os"
import "core:os/os2"
import "core:sync/chan"
import "core:thread"
import "core:log"
import "core:time"
import vmem "core:mem/virtual"

Lua_Print_Data :: struct {
  _context: ^runtime.Context,
}

lua_vm_print :: proc "c" (L: ^lua.State) -> int {
  nargs := lua.gettop(L)
  // log.debug(nargs)
  return 0
}

lua_allocator :: proc "c" (ud: rawptr, ptr: rawptr, osize, nsize: c.size_t) -> (buf: rawptr) {
	old_size := int(osize)
	new_size := int(nsize)
	mem_data := (^Mem_Data)(ud)^
  context = mem_data.ctx^
  (^Mem_Data)(ud).mem_count += nsize

	if ptr == nil {
		data, err := runtime.mem_alloc(new_size)
		return raw_data(data) if err == .None else nil
	} else {
		if nsize > 0 {
			data, err := runtime.mem_resize(ptr, old_size, new_size)
			return raw_data(data) if err == .None else nil
		} else {
			runtime.mem_free(ptr)
			return
		}
	}
}

Mem_Data :: struct {
  ctx: ^runtime.Context,
  mem_count: uint,
}

VM_Command :: enum {
  Halt,
  Execute,
}

Lua_VM_Data :: struct {
  commands_chan: chan.Chan(VM_Command, .Recv),
  source: string,
}

start_lua_vm :: proc(lua_vm_data: Lua_VM_Data) {
  _context := context
  mem_data := Mem_Data{
    ctx = &_context,
  }
  L := lua.newstate(lua_allocator, &mem_data)
  defer lua.close(L)
  lua.L_openlibs(L)
  for {
    cmd, ok := chan.recv(lua_vm_data.commands_chan)
    if !ok {
      log.debug("cmd channel closed")
      break
    }

    cstr_src := strings.clone_to_cstring(lua_vm_data.source); defer delete(cstr_src)
    compile_err_code := lua.L_loadstring(L, cstr_src)
    if compile_err_code != .OK {
      log.errorf("error compiling lua script: %s", lua.tostring(L, -1))
      lua.pop(L, 1)
      continue
    }

    exec_err_code := lua.pcall(L, 0, 1, 0)
    if exec_err_code != 0 {
      log.errorf("lua runtime error: %s", lua.tostring(L, -1))
      lua.pop(L, 1)
      continue
    }

    str := lua.tostring(L, -1)
    log.debug(str)
    log.debug(mem_data.mem_count)
    log.debug("hello world")

  }
}

Threadsafe_Logger_Data :: struct {
  log_chan: chan.Chan(string, .Both),
  arena: vmem.Arena,
}

create_threadsafe_queue_logger :: proc() -> (log.Logger, bool) {

  arena: vmem.Arena
  arena_err := vmem.arena_init_growing(&arena)
  if arena_err != nil {
    return log.Logger{}, false
  }

  arena_alloc := vmem.arena_allocator(&arena)

  MAX_MESSAGES :: 64
  c, err := chan.create(chan.Chan(string), MAX_MESSAGES, arena_alloc)
  if err != nil {
    fmt.eprintfln("Couldn't create logger, err: %v", err)
    return log.Logger{}, false
  }


  thsafe_logger_data := Threadsafe_Logger_Data {
    log_chan = c,
    arena = arena,
  }

  return log.Logger {
    procedure = threadsafely_log,
    data = new_clone(thsafe_logger_data),
    lowest_level = .Debug,
    options = {.Level, .Terminal_Color, .Short_File_Path, .Line, .Procedure, .Thread_Id} 
  }, false
}

threadsafely_log :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: bit_set[runtime.Logger_Option], location := #caller_location) {
  logger_data := cast(^Threadsafe_Logger_Data)data
  c := logger_data.log_chan
  backing: [1024]byte
  buf := strings.builder_from_bytes(backing[:])

  log.do_level_header(options, &buf, level)
  log.do_location_header(options, &buf, location)
  fmt.sbprintf(&buf, "[{}] ", os.current_thread_id())
  fmt.sbprintf(&buf, "%s", text)
  chan.send(c, strings.clone(strings.to_string(buf)))
}

main :: proc() {
  c, err := chan.create(chan.Chan(VM_Command), context.allocator)
  assert(err == .None)
  defer chan.destroy(c)

  thsafe_logger, logger_err := create_threadsafe_queue_logger()
  if logger_err {
    os.exit(1)
  }

  ctx := runtime.default_context()
  ctx.logger = thsafe_logger
  context.logger = thsafe_logger
  log.debug("hello from main thread")

  src_path := "lua_src/fib.lua"
  lua_source, lsrc_err := os2.read_entire_file(src_path, context.allocator) 
  if lsrc_err != nil {
    fmt.eprintln(lsrc_err)
    os.exit(1)
  }

  lua_vm_data := Lua_VM_Data {
    commands_chan = chan.as_recv(c),
    source = string(lua_source),
  }
  lua_thread := thread.create_and_start_with_poly_data(lua_vm_data, start_lua_vm, ctx)
  for i in 0..<3 {
    chan.send(c, VM_Command.Execute)
    log.debug("sleeping")
    time.sleep(time.Second * 1)
  }

  log_chan := cast(^chan.Chan(string, .Both))thsafe_logger.data
  fmt.println(log_chan)
  for i in 0..=chan.len(log_chan) {
    msg, _ := chan.recv(chan.as_recv(log_chan^))
    fmt.println(msg)
  }
}
