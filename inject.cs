// Windows counterpart of inject.py, compiled at launch by launch.ps1 (Add-Type).
//
// A minimal debugger: start the game under DEBUG_ONLY_THIS_PROCESS, set a
// software breakpoint on luaL_loadbuffer (exported by lua51.dll), and wait for
// the call whose chunk name (4th argument, r9) is "@main.lua". At that point
// rcx is the lua_State*. The game thread is redirected to a few bytes of
// generated code that call luaL_loadfile(L, loader) + lua_pcall(L, 0, 0, 0)
// and trap back; its original context is then restored and the debugger
// detaches. Nothing on disk is modified, and any failure leaves the game
// running unmodified.
//
// x64 only. Written for C# 5 (the compiler that ships with Windows
// PowerShell 5.1): no string interpolation, no expression-bodied members.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace SlotboundTweaks
{
    public static class Injector
    {
        const string TRIGGER_CHUNK = "@main.lua";

        // ---------------------------------------------------------------- Win32
        const uint DEBUG_ONLY_THIS_PROCESS = 0x00000002;
        const uint STARTF_USESTDHANDLES = 0x00000100;
        const uint DBG_CONTINUE = 0x00010002;
        const uint DBG_EXCEPTION_NOT_HANDLED = 0x80010001;
        const uint EXCEPTION_BREAKPOINT = 0x80000003;
        const uint EXCEPTION_SINGLE_STEP = 0x80000004;
        const uint THREAD_ACCESS = 0x0008 | 0x0010 | 0x0002 | 0x0040; // get/set context, suspend, query
        const uint MEM_COMMIT_RESERVE = 0x3000, MEM_RELEASE = 0x8000, PAGE_EXECUTE_READWRITE = 0x40;
        const uint CONTEXT_FULL = 0x0010000B; // AMD64 | CONTROL | INTEGER | FLOATING_POINT

        // CONTEXT (x64) offsets
        const int CTX_SIZE = 1232, CTX_FLAGS = 0x30, CTX_EFLAGS = 0x44,
                  CTX_RCX = 0x80, CTX_RSP = 0x98, CTX_R9 = 0xC0, CTX_RIP = 0xF8;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb; public string lpReserved, lpDesktop, lpTitle;
            public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute;
            public uint dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2;
            public IntPtr hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

        [StructLayout(LayoutKind.Sequential)]
        struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
            uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa,
            uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WaitForDebugEvent(IntPtr ev, uint ms);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ContinueDebugEvent(int pid, int tid, uint status);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DebugActiveProcessStop(int pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DebugSetProcessKillOnExit(bool kill);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool FlushInstructionCache(IntPtr hp, IntPtr addr, IntPtr size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint protect);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, IntPtr size, uint type);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenThread(uint access, bool inherit, int tid);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetThreadContext(IntPtr ht, IntPtr ctx);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetThreadContext(IntPtr ht, IntPtr ctx);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool IsWow64Process(IntPtr hp, out bool wow64);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int GetFinalPathNameByHandleW(IntPtr h, StringBuilder name, int size, uint flags);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int GetShortPathNameW(string longPath, StringBuilder shortPath, int size);

        // ---------------------------------------------------------------- state
        static StreamWriter logw;
        static IntPtr hProc;
        static IntPtr ctxRaw, ctx;

        static void Log(string msg)
        {
            if (logw == null) return;
            logw.WriteLine("[inject] " + DateTime.Now.ToString("HH:mm:ss.fff") + " " + msg);
            logw.Flush();
        }

        static string Hex(long v) { return "0x" + v.ToString("x"); }

        static byte[] Read(long addr, long size)
        {
            if (size <= 0 || size > (64L << 20)) return null;
            byte[] buf = new byte[size];
            IntPtr got;
            if (!ReadProcessMemory(hProc, new IntPtr(addr), buf, new IntPtr(size), out got) || got.ToInt64() != size)
                return null;
            return buf;
        }

        static bool Write(long addr, byte[] data)
        {
            IntPtr put;
            bool ok = WriteProcessMemory(hProc, new IntPtr(addr), data, new IntPtr(data.Length), out put);
            FlushInstructionCache(hProc, new IntPtr(addr), new IntPtr(data.Length));
            return ok && put.ToInt64() == data.Length;
        }

        static string ReadCString(long addr, int max)
        {
            if (addr == 0) return null;
            var sb = new List<byte>();
            for (long p = addr; sb.Count < max; p += 64)
            {
                // read in small chunks, stop at the first NUL; a chunk may cross into an unmapped page
                byte[] b = Read(p, 64);
                if (b == null) b = Read(p, 1);
                if (b == null) break;
                foreach (byte c in b) { if (c == 0) return Encoding.UTF8.GetString(sb.ToArray()); sb.Add(c); }
            }
            return Encoding.UTF8.GetString(sb.ToArray());
        }

        // Path of a module image from the file handle in its debug event (the
        // loader's module list does not have it yet at that point).
        static string FileName(IntPtr hFile)
        {
            if (hFile == IntPtr.Zero) return "?";
            var sb = new StringBuilder(1024);
            int n = GetFinalPathNameByHandleW(hFile, sb, sb.Capacity, 0);
            if (n <= 0 || n >= sb.Capacity) return "?";
            string p = sb.ToString();
            return p.StartsWith(@"\\?\") ? p.Substring(4) : p;
        }

        static IntPtr OpenThreadForContext(int tid) { return OpenThread(THREAD_ACCESS, false, tid); }

        static bool GetCtx(IntPtr ht)
        {
            Marshal.WriteInt32(ctx, CTX_FLAGS, unchecked((int)CONTEXT_FULL));
            return GetThreadContext(ht, ctx);
        }

        static long CtxGet(int off) { return Marshal.ReadInt64(ctx, off); }
        static void CtxSet(int off, long v) { Marshal.WriteInt64(ctx, off, v); }

        // ---------------------------------------------------------------- PE exports
        static uint U32(byte[] b, long o) { return BitConverter.ToUInt32(b, (int)o); }

        static Dictionary<string, long> Exports(long mod, HashSet<string> want)
        {
            var res = new Dictionary<string, long>();
            byte[] dos = Read(mod, 0x40);
            if (dos == null || dos[0] != 'M' || dos[1] != 'Z') return res;
            int lfanew = BitConverter.ToInt32(dos, 0x3C);
            byte[] nt = Read(mod + lfanew, 0x108);
            if (nt == null || U32(nt, 0) != 0x00004550) return res;
            ushort magic = BitConverter.ToUInt16(nt, 24);
            int dd = 24 + (magic == 0x20B ? 112 : 96);
            uint expRva = U32(nt, dd), expSize = U32(nt, dd + 4);
            if (expRva == 0 || expSize < 40) return res;
            byte[] ed = Read(mod + expRva, expSize);
            if (ed == null) return res;
            uint nFun = U32(ed, 20), nNames = U32(ed, 24), aFun = U32(ed, 28), aNames = U32(ed, 32), aOrd = U32(ed, 36);
            if (nNames == 0 || nNames > 100000 || nFun > 100000) return res;
            byte[] names = Read(mod + aNames, nNames * 4L), ords = Read(mod + aOrd, nNames * 2L), funs = Read(mod + aFun, nFun * 4L);
            if (names == null || ords == null || funs == null) return res;
            for (uint i = 0; i < nNames; i++)
            {
                uint nameRva = U32(names, i * 4L);
                string name;
                if (nameRva >= expRva && nameRva < expRva + expSize)
                {
                    int s = (int)(nameRva - expRva), e = s;
                    while (e < ed.Length && ed[e] != 0) e++;
                    name = Encoding.ASCII.GetString(ed, s, e - s);
                }
                else name = ReadCString(mod + nameRva, 128);
                if (name == null || !want.Contains(name)) continue;
                ushort ord = BitConverter.ToUInt16(ords, (int)(i * 2));
                if (ord >= nFun) continue;
                uint fRva = U32(funs, ord * 4L);
                if (fRva >= expRva && fRva < expRva + expSize) continue; // forwarded export
                res[name] = mod + fRva;
            }
            return res;
        }

        // ---------------------------------------------------------------- generated code
        class Asm
        {
            public List<byte> b = new List<byte>();
            public int Pos { get { return b.Count; } }
            public void Emit(params byte[] x) { b.AddRange(x); }
            public void Imm64(byte rex, byte op, long v) { Emit(rex, op); b.AddRange(BitConverter.GetBytes(v)); }
            public void MovRcx(long v) { Imm64(0x48, 0xB9, v); }
            public void MovRdx(long v) { Imm64(0x48, 0xBA, v); }
            public void MovRax(long v) { Imm64(0x48, 0xB8, v); }
            public void MovR10(long v) { Imm64(0x49, 0xBA, v); }
            public void MovEdx(int v) { Emit(0xBA); b.AddRange(BitConverter.GetBytes(v)); }
            public void CallRax() { Emit(0xFF, 0xD0); }
            public int Jnz() { Emit(0x75, 0x00); return Pos - 1; }
            public void Patch(int at, int target) { b[at] = (byte)(target - (at + 1)); }
        }

        // Layout of the remote block: code at +0, data (results) at +0x200, loader path at +0x300.
        const int DATA_OFF = 0x200, PATH_OFF = 0x300;

        static byte[] BuildCode(long block, long L, Dictionary<string, long> api,
                                out int okAt, out int msgAt, out int errAt)
        {
            long data = block + DATA_OFF, path = block + PATH_OFF;
            var a = new Asm();
            a.Emit(0x48, 0x83, 0xEC, 0x20);                       // sub rsp, 0x20 (shadow space)
            a.MovRcx(L); a.MovRdx(path); a.MovRax(api["luaL_loadfile"]); a.CallRax();
            a.MovR10(data); a.Emit(0x41, 0x89, 0x02);             // mov [r10], eax
            a.Emit(0x85, 0xC0); int j1 = a.Jnz();                 // test eax, eax; jnz err
            a.MovRcx(L); a.Emit(0x31, 0xD2);                      // xor edx, edx
            a.Emit(0x45, 0x31, 0xC0); a.Emit(0x45, 0x31, 0xC9);   // xor r8d, r8d; xor r9d, r9d
            a.MovRax(api["lua_pcall"]); a.CallRax();
            a.MovR10(data); a.Emit(0x41, 0x89, 0x42, 0x04);       // mov [r10+4], eax
            a.Emit(0x85, 0xC0); int j2 = a.Jnz();
            okAt = a.Pos; a.Emit(0xCC);                           // int3: success
            int err = a.Pos; a.Patch(j1, err); a.Patch(j2, err);
            a.MovRcx(L); a.MovEdx(-1); a.Emit(0x45, 0x31, 0xC0);
            a.MovRax(api["lua_tolstring"]); a.CallRax();
            a.MovR10(data); a.Emit(0x49, 0x89, 0x42, 0x08);       // mov [r10+8], rax
            msgAt = a.Pos; a.Emit(0xCC);                          // int3: error message ready
            a.MovRcx(L); a.MovEdx(-2); a.MovRax(api["lua_settop"]); a.CallRax();
            errAt = a.Pos; a.Emit(0xCC);                          // int3: error handled
            if (a.Pos > DATA_OFF) throw new Exception("generated code too large");
            return a.b.ToArray();
        }

        // luaL_loadfile takes a char* in the ANSI code page; loader.lua derives
        // its root from that path, so use forward slashes.
        static byte[] LoaderPathBytes(string path)
        {
            string p = path;
            bool ascii = true;
            foreach (char c in p) if (c > 127) { ascii = false; break; }
            if (!ascii)
            {
                var sb = new StringBuilder(1024);
                if (GetShortPathNameW(p, sb, sb.Capacity) > 0) p = sb.ToString();
            }
            p = p.Replace('\\', '/');
            byte[] s = Encoding.Default.GetBytes(p);
            byte[] z = new byte[s.Length + 1];
            Array.Copy(s, z, s.Length);
            return z;
        }

        static string Quote(string arg)
        {
            if (arg.Length > 0 && arg.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return arg;
            var sb = new StringBuilder("\"");
            int bs = 0;
            foreach (char c in arg)
            {
                if (c == '\\') { bs++; continue; }
                if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); }
                else { sb.Append('\\', bs); sb.Append(c); }
                bs = 0;
            }
            sb.Append('\\', bs * 2);
            sb.Append('"');
            return sb.ToString();
        }

        // ---------------------------------------------------------------- main
        // Starts the game and injects loader.lua. Returns the game's pid (0 if it
        // could not be started). Injection failures are logged; the game keeps running.
        public static int Run(string game, string[] args, string loader, string outPath, string logPath, int timeoutSec)
        {
            // Logging must never stop the launch (antivirus scanners briefly lock files).
            for (int i = 0; i < 10 && logw == null; i++)
            {
                try
                {
                    var fs = new FileStream(logPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                    logw = new StreamWriter(fs, new UTF8Encoding(false));
                }
                catch (IOException) { System.Threading.Thread.Sleep(50); }
                catch (UnauthorizedAccessException) { break; }
            }
            try { return RunInner(game, args, loader, outPath, timeoutSec); }
            catch (Exception e) { Log("ERROR: " + e.Message + " (the game keeps running without tweaks)"); return 0; }
            finally { if (logw != null) logw.Dispose(); logw = null; }
        }

        static int RunInner(string game, string[] args, string loader, string outPath, int timeoutSec)
        {
            var sa = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
            // FILE_APPEND_DATA | SYNCHRONIZE, share read/write, OPEN_ALWAYS
            IntPtr hOut = CreateFileW(outPath, 0x0004 | 0x00100000, 0x1 | 0x2, ref sa, 4, 0x80, IntPtr.Zero);
            if (hOut == new IntPtr(-1)) hOut = IntPtr.Zero;

            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            if (hOut != IntPtr.Zero) { si.dwFlags = STARTF_USESTDHANDLES; si.hStdOutput = hOut; si.hStdError = hOut; }

            var cmd = new StringBuilder(Quote(game));
            foreach (string a in args) cmd.Append(' ').Append(Quote(a));

            // Processes started under a debugger get the slow debug heap unless this is set.
            Environment.SetEnvironmentVariable("_NO_DEBUG_HEAP", "1");

            PROCESS_INFORMATION pi;
            if (!CreateProcessW(game, cmd, IntPtr.Zero, IntPtr.Zero, hOut != IntPtr.Zero, DEBUG_ONLY_THIS_PROCESS,
                                IntPtr.Zero, Path.GetDirectoryName(game), ref si, out pi))
            {
                int e = Marshal.GetLastWin32Error();
                if (hOut != IntPtr.Zero) CloseHandle(hOut);
                throw new Exception("CreateProcess failed (" + e + "): " + game);
            }
            if (hOut != IntPtr.Zero) CloseHandle(hOut);
            // If this launcher dies, detach instead of killing the game.
            DebugSetProcessKillOnExit(false);
            hProc = pi.hProcess;
            Log("game pid " + pi.dwProcessId + ": " + cmd);

            ctxRaw = Marshal.AllocHGlobal(CTX_SIZE + 16);
            ctx = new IntPtr((ctxRaw.ToInt64() + 15) & ~15L);
            try
            {
                bool wow64;
                if (IsWow64Process(hProc, out wow64) && wow64) throw new Exception("32-bit game is not supported");
                Debug(pi.dwProcessId, loader, timeoutSec);
            }
            catch (Exception e) { Log("ERROR: " + e.Message + " (the game keeps running without tweaks)"); }
            finally { Marshal.FreeHGlobal(ctxRaw); }
            return pi.dwProcessId;
        }

        static readonly HashSet<string> API = new HashSet<string> {
            "luaL_loadbuffer", "luaL_loadfile", "lua_pcall", "lua_tolstring", "lua_settop" };

        static void Debug(int pid, string loader, int timeoutSec)
        {
            IntPtr ev = Marshal.AllocHGlobal(256);
            var modules = new List<long>();
            var moduleNames = new List<string>();
            int scanned = 0;
            Dictionary<string, long> api = null;
            long bp = 0; byte origByte = 0;
            bool sysBp = false, stepping = false, attached = true;
            int phase = 0;                 // 0 waiting for main.lua, 1 running generated code, 2 done
            long block = 0; int okAt = 0, msgAt = 0, errAt = 0;
            byte[] saved = new byte[CTX_SIZE];
            int injTid = 0, loads = 0, pendingTid = 0;
            bool pending = false;
            string luaErr = null;
            DateTime deadline = DateTime.Now.AddSeconds(timeoutSec);

            Action resolve = delegate
            {
                for (; scanned < modules.Count && api == null; scanned++)
                {
                    var ex = Exports(modules[scanned], API);
                    if (ex.Count != API.Count) continue;
                    api = ex;
                    string name = moduleNames[scanned];
                    bp = api["luaL_loadbuffer"];
                    byte[] ob = Read(bp, 1);
                    if (ob == null || !Write(bp, new byte[] { 0xCC })) throw new Exception("cannot set breakpoint at " + Hex(bp));
                    origByte = ob[0];
                    Log("lua API in " + name + " @" + Hex(modules[scanned]) + "; breakpoint on luaL_loadbuffer " + Hex(bp));
                }
            };

            try
            {
                while (phase != 2)
                {
                    if (phase == 0 && DateTime.Now > deadline) throw new Exception("timed out waiting for " + TRIGGER_CHUNK);
                    if (!WaitForDebugEvent(ev, 500)) continue;
                    uint code = (uint)Marshal.ReadInt32(ev, 0);
                    int evPid = Marshal.ReadInt32(ev, 4), tid = Marshal.ReadInt32(ev, 8);
                    pending = true; pendingTid = tid;
                    IntPtr u = new IntPtr(ev.ToInt64() + 16); // union, 8-aligned on x64
                    uint status = DBG_CONTINUE;

                    switch (code)
                    {
                        case 3: // CREATE_PROCESS_DEBUG_EVENT
                            moduleNames.Add(FileName(Marshal.ReadIntPtr(u, 0)));
                            CloseHandle(Marshal.ReadIntPtr(u, 0));
                            modules.Add(Marshal.ReadInt64(u, 24));
                            break;
                        case 6: // LOAD_DLL_DEBUG_EVENT
                            moduleNames.Add(FileName(Marshal.ReadIntPtr(u, 0)));
                            CloseHandle(Marshal.ReadIntPtr(u, 0));
                            modules.Add(Marshal.ReadInt64(u, 8));
                            if (sysBp && api == null) resolve();
                            break;
                        case 5: // EXIT_PROCESS_DEBUG_EVENT
                            attached = false;
                            throw new Exception("game exited before injection (exit code " + Marshal.ReadInt32(u, 0) + ")");
                        case 1: // EXCEPTION_DEBUG_EVENT
                        {
                            uint exc = (uint)Marshal.ReadInt32(u, 0);
                            long addr = Marshal.ReadInt64(u, 16);
                            if (exc == EXCEPTION_BREAKPOINT && !sysBp)
                            {
                                // loader breakpoint: static imports (love.dll, lua51.dll) are mapped and relocated
                                sysBp = true;
                                resolve();
                                if (api == null) Log("lua API not loaded yet; watching DLL loads");
                            }
                            else if (exc == EXCEPTION_BREAKPOINT && phase == 0 && addr == bp)
                            {
                                IntPtr ht = OpenThreadForContext(tid);
                                try
                                {
                                    if (!GetCtx(ht)) throw new Exception("GetThreadContext failed");
                                    CtxSet(CTX_RIP, bp);
                                    string name = ReadCString(CtxGet(CTX_R9), 256);
                                    loads++;
                                    Write(bp, new byte[] { origByte });
                                    if (name != TRIGGER_CHUNK)
                                    {
                                        // step over the original instruction, then re-arm (EXCEPTION_SINGLE_STEP)
                                        CtxSet(CTX_EFLAGS, CtxGet(CTX_EFLAGS) | 0x100);
                                        stepping = true;
                                    }
                                    else
                                    {
                                        long L = CtxGet(CTX_RCX);
                                        Marshal.Copy(ctx, saved, 0, CTX_SIZE);
                                        block = VirtualAllocEx(hProc, IntPtr.Zero, new IntPtr(0x1000), MEM_COMMIT_RESERVE, PAGE_EXECUTE_READWRITE).ToInt64();
                                        if (block == 0) throw new Exception("VirtualAllocEx failed");
                                        byte[] path = LoaderPathBytes(loader);
                                        if (path.Length > 0x1000 - PATH_OFF) throw new Exception("loader path too long");
                                        byte[] img = new byte[0x1000];
                                        byte[] codeBytes = BuildCode(block, L, api, out okAt, out msgAt, out errAt);
                                        Array.Copy(codeBytes, img, codeBytes.Length);
                                        Array.Copy(BitConverter.GetBytes(-999), 0, img, DATA_OFF, 4);
                                        Array.Copy(BitConverter.GetBytes(-999), 0, img, DATA_OFF + 4, 4);
                                        Array.Copy(path, 0, img, PATH_OFF, path.Length);
                                        if (!Write(block, img)) throw new Exception("cannot write generated code");
                                        long rsp = (CtxGet(CTX_RSP) - 0x100) & ~0xFL;
                                        CtxSet(CTX_RSP, rsp);
                                        CtxSet(CTX_RIP, block);
                                        phase = 1; injTid = tid;
                                        Log("hit " + TRIGGER_CHUNK + " (luaL_loadbuffer call #" + loads + ") on thread " + tid + ", lua_State " + Hex(L));
                                    }
                                    if (!SetThreadContext(ht, ctx)) throw new Exception("SetThreadContext failed");
                                }
                                finally { CloseHandle(ht); }
                            }
                            else if (exc == EXCEPTION_SINGLE_STEP && stepping)
                            {
                                stepping = false;
                                if (phase == 0) Write(bp, new byte[] { 0xCC });
                            }
                            else if (exc == EXCEPTION_BREAKPOINT && phase == 1 && tid == injTid &&
                                     (addr == block + okAt || addr == block + msgAt || addr == block + errAt))
                            {
                                IntPtr ht = OpenThreadForContext(tid);
                                try
                                {
                                    byte[] data = Read(block + DATA_OFF, 16);
                                    if (addr == block + msgAt)
                                    {
                                        luaErr = ReadCString(BitConverter.ToInt64(data, 8), 4096);
                                        if (!GetCtx(ht)) throw new Exception("GetThreadContext failed");
                                        CtxSet(CTX_RIP, addr + 1);
                                        SetThreadContext(ht, ctx);
                                    }
                                    else
                                    {
                                        Marshal.Copy(saved, 0, ctx, CTX_SIZE);
                                        if (!SetThreadContext(ht, ctx)) throw new Exception("cannot restore game thread context");
                                        phase = 2;
                                        if (addr == block + okAt) Log("loader.lua injected into lua_State " + Hex(BitConverter.ToInt64(saved, CTX_RCX)));
                                        else Log("lua error (luaL_loadfile=" + BitConverter.ToInt32(data, 0) + ", lua_pcall=" +
                                                 BitConverter.ToInt32(data, 4) + "): " + luaErr);
                                    }
                                }
                                finally { CloseHandle(ht); }
                            }
                            else status = DBG_EXCEPTION_NOT_HANDLED;
                            break;
                        }
                    }
                    ContinueDebugEvent(evPid, tid, status);
                    pending = false;
                }
            }
            catch (Exception e)
            {
                Log("ERROR: " + e.Message + " (the game keeps running without tweaks)");
                if (phase == 0 && bp != 0 && attached) Write(bp, new byte[] { origByte });
                if (phase == 1) Log("WARNING: detaching while generated code is running");
                if (pending && attached) ContinueDebugEvent(pid, pendingTid, DBG_CONTINUE);
            }
            finally
            {
                Marshal.FreeHGlobal(ev);
                if (attached)
                {
                    if (block != 0 && phase == 2) VirtualFreeEx(hProc, new IntPtr(block), IntPtr.Zero, MEM_RELEASE);
                    if (DebugActiveProcessStop(pid)) Log("detached; game keeps running");
                    else Log("detach failed (" + Marshal.GetLastWin32Error() + ")");
                }
            }
        }
    }
}
