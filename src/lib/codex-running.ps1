# Windows ships SQLite. Open Codex metadata read-only; never read message bodies.
if (-not ('CodexWidget.MetadataDb' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace CodexWidget {
 public static class MetadataDb {
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] path,out IntPtr db,int flags,IntPtr vfs);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db,int ms);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db,byte[] sql,int n,out IntPtr stmt,IntPtr tail);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_count(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt,int column);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt,int column);
  public static string[][] Read(string path,string sql) {
   IntPtr db=IntPtr.Zero, stmt=IntPtr.Zero;
   try {
    if(sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"),out db,1|32768,IntPtr.Zero)!=0) throw new Exception("Cannot open Codex metadata read-only");
    sqlite3_busy_timeout(db,100);
    if(sqlite3_prepare_v2(db,Encoding.UTF8.GetBytes(sql+"\0"),-1,out stmt,IntPtr.Zero)!=0) throw new Exception("Unsupported Codex metadata schema");
    var rows=new List<string[]>(); int code;
    while((code=sqlite3_step(stmt))==100) {
     var row=new string[sqlite3_column_count(stmt)];
     for(int i=0;i<row.Length;i++) {
      IntPtr p=sqlite3_column_text(stmt,i); int n=sqlite3_column_bytes(stmt,i);
      if(p==IntPtr.Zero) continue;
      var bytes=new byte[n]; Marshal.Copy(p,bytes,0,n); row[i]=Encoding.UTF8.GetString(bytes);
     }
     rows.Add(row);
    }
    if(code!=101) throw new Exception("Codex metadata is busy or unavailable");
    return rows.ToArray();
   } finally { if(stmt!=IntPtr.Zero) sqlite3_finalize(stmt); if(db!=IntPtr.Zero) sqlite3_close(db); }
  }
 }
}
'@
}
function Get-LocalCodexActivity {
    $homePath=if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $statePath=Join-Path $homePath 'state_5.sqlite'
    $historyPath=Join-Path $homePath 'thread_history_1.sqlite'
    if (-not (Test-Path $statePath) -or -not (Test-Path $historyPath)) { return $null }
    $running=@{}
    foreach ($row in [CodexWidget.MetadataDb]::Read($historyPath,"SELECT DISTINCT thread_id FROM thread_turns WHERE status='inProgress' AND completed_at IS NULL")) { $running[$row[0]]=$true }
    $threads=@(foreach ($row in [CodexWidget.MetadataDb]::Read($statePath,'SELECT id,updated_at FROM threads WHERE archived=0 ORDER BY updated_at DESC LIMIT 100')) {
        [pscustomobject]@{id=$row[0];updatedAt=[long]$row[1];widgetTurnStatus=$(if ($running.ContainsKey($row[0])) { 'inProgress' } else { 'completed' })}
    })
    return [pscustomobject]@{widgetThreads=$threads}
}
