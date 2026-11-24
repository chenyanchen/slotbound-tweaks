"""lldb driver: launch Slotbound, wait for the game's protected bootstrap to
load `@main.lua`, run loader.lua inside the game's Lua state, then detach.

Nothing on disk is modified: the game decrypts and verifies its own package as
usual; this only executes extra Lua in the running process.

Driven by env vars set in launch.sh:
  SB_GAME    game executable
  SB_LOADER  absolute path of loader.lua
  SB_OUT     file that receives the game's stdout/stderr
  SB_PID     file that receives the game's pid
  SB_ARGS    JSON list of extra args for the game
"""
import json
import os
import time

import lldb

TRIGGER_CHUNK = "@main.lua"
TIMEOUT_SEC = 120
DRIVER_VARS = {"SB_GAME", "SB_LOADER", "SB_OUT", "SB_PID", "SB_ARGS"}


def log(msg):
    print("[inject] " + msg, flush=True)


def c_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sym_addr(target, name):
    for ctx in target.FindSymbols(name):
        addr = ctx.GetSymbol().GetStartAddress().GetLoadAddress(target)
        if addr != lldb.LLDB_INVALID_ADDRESS:
            return addr
    raise RuntimeError("symbol not found: " + name)


def evaluate(frame, expr):
    opts = lldb.SBExpressionOptions()
    opts.SetIgnoreBreakpoints(True)
    opts.SetTryAllThreads(False)
    opts.SetUnwindOnError(True)
    opts.SetTimeoutInMicroSeconds(15_000_000)
    v = frame.EvaluateExpression(expr, opts)
    if v.GetError().Fail():
        raise RuntimeError("expression failed: %s (%s)" % (v.GetError().GetCString(), expr))
    return v


def inject(target, frame, loader_path):
    # We are stopped at luaL_loadbuffer(L, buf, size, "@main.lua"); x0 is L.
    L = frame.FindRegister("x0").GetValueAsUnsigned()
    loadfile = sym_addr(target, "luaL_loadfile")
    pcall = sym_addr(target, "lua_pcall")
    tolstring = sym_addr(target, "lua_tolstring")
    settop = sym_addr(target, "lua_settop")

    rc = evaluate(frame, "(int)((int(*)(void*,const char*))%#x)((void*)%#x, %s)"
                  % (loadfile, L, c_string(loader_path))).GetValueAsSigned()
    stage = "load"
    if rc == 0:
        stage = "run"
        rc = evaluate(frame, "(int)((int(*)(void*,int,int,int))%#x)((void*)%#x,0,0,0)"
                      % (pcall, L)).GetValueAsSigned()
    if rc != 0:
        msg = evaluate(frame, "(const char*)((const char*(*)(void*,int,unsigned long*))%#x)((void*)%#x,-1,(unsigned long*)0)"
                       % (tolstring, L)).GetSummary()
        log("lua error: %s" % msg)
        evaluate(frame, "(int)(((void(*)(void*,int))%#x)((void*)%#x,-2), 0)" % (settop, L))
        raise RuntimeError("loader %s failed (rc=%d)" % (stage, rc))
    log("loader.lua injected into lua_State %#x" % L)


def stop_thread(process):
    for t in process:
        if t.GetStopReason() == lldb.eStopReasonBreakpoint:
            return t
    return None


def run(debugger):
    game = os.environ["SB_GAME"]
    loader = os.environ["SB_LOADER"]
    out = os.environ["SB_OUT"]
    pid_file = os.environ["SB_PID"]
    args = json.loads(os.environ.get("SB_ARGS", "[]"))

    debugger.SetAsync(False)
    target = debugger.CreateTarget(game)
    if not target:
        raise RuntimeError("cannot create target for " + game)
    bp = target.BreakpointCreateByName("luaL_loadbuffer")

    info = lldb.SBLaunchInfo(args)
    env = lldb.SBEnvironment()
    for k, v in os.environ.items():
        if k in DRIVER_VARS or k.startswith("DYLD_"):
            continue
        env.Set(k, v, True)
    info.SetEnvironment(env, False)
    info.AddOpenFileAction(0, "/dev/null", True, False)
    info.AddOpenFileAction(1, out, False, True)
    info.AddOpenFileAction(2, out, False, True)

    err = lldb.SBError()
    process = target.Launch(info, err)
    if err.Fail() or not process:
        raise RuntimeError("launch failed: %s" % err.GetCString())
    with open(pid_file, "w") as f:
        f.write(str(process.GetProcessID()))
    log("game pid %d" % process.GetProcessID())

    deadline = time.time() + TIMEOUT_SEC
    try:
        while time.time() < deadline:
            state = process.GetState()
            if state in (lldb.eStateExited, lldb.eStateCrashed, lldb.eStateDetached):
                raise RuntimeError("game ended before injection (state %d)" % state)
            if state != lldb.eStateStopped:
                process.Continue()
                continue
            thread = stop_thread(process)
            if thread is None:
                process.Continue()
                continue
            frame = thread.GetFrameAtIndex(0)
            namep = frame.FindRegister("x3").GetValueAsUnsigned()
            name = process.ReadCStringFromMemory(namep, 256, lldb.SBError()) if namep else ""
            if name == TRIGGER_CHUNK:
                bp.SetEnabled(False)
                inject(target, frame, loader)
                return
            process.Continue()
        raise RuntimeError("timed out waiting for %s" % TRIGGER_CHUNK)
    finally:
        target.BreakpointDelete(bp.GetID())
        if process.GetState() in (lldb.eStateStopped, lldb.eStateRunning):
            process.Detach()
            log("detached; game keeps running")


def __lldb_init_module(debugger, internal_dict):
    try:
        run(debugger)
    except Exception as e:  # noqa: BLE001 - report everything to the log
        log("ERROR: %s (the game keeps running without tweaks)" % e)
