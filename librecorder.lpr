library librecorder;

{$mode ObjFPC}{$H+}

uses
  Classes, SysUtils,
  recorder;

{$i simbaplugin.inc}

procedure _Lape_Recorder_Create(const Params: PParamArray; const Result: Pointer); cdecl;
begin
  PRecorder(Result)^ := TRecorder.Create(PInteger(Params^[0])^, PString(Params^[1])^, PInteger(Params^[2])^, PInteger(Params^[3])^, PRecorderGetFrame(Params^[4])^, PRecorderGetTerminated(Params^[5])^);
end;

procedure _Lape_Recorder_Free(const Params: PParamArray); cdecl;
begin
  PRecorder(Params^[0])^.Free();
end;

procedure _Lape_Recorder_SetFFMPEG(const Params: PParamArray); cdecl;
begin
  PRecorder(Params^[0])^.FFMPEG := PString(Params^[1])^;
end;

procedure _Lape_Recorder_GetFFMPEG(const Params: PParamArray; const Result: Pointer); cdecl;
begin
  PString(Result)^ := PRecorder(Params^[0])^.FFMPEG;
end;

procedure _Lape_Recorder_Run(const Params: PParamArray); cdecl;
begin
  PRecorder(Params^[0])^.Run(PBoolean(Params^[1])^);
end;

begin
  addGlobalType('type Pointer', 'TRecorder');

  addGlobalType('native(type function(Sender: TRecorder): Pointer)', 'TRecorderGetFrame');
  addGlobalType('native(type function(Sender: TRecorder): Boolean)', 'TRecorderGetTerminated');

  addGlobalFunc('function TRecorder.Create(Seconds: Integer; Directory: String; Width, Height: Integer; GetFrameFunc: TRecorderGetFrame; GetTerminatedFunc: TRecorderGetTerminated): TRecorder; static; overload; native;', @_Lape_Recorder_Create);
  addGlobalFunc('procedure TRecorder.Free; native;', @_Lape_Recorder_Free);

  addGlobalFunc('function TRecorder.GetFFMPEG: String; native;', @_Lape_Recorder_GetFFMPEG);
  addGlobalFunc('procedure TRecorder.SetFFMPEG(Path: String); native;', @_Lape_Recorder_SetFFMPEG);
  addGlobalFunc('procedure TRecorder.Run(Debugging: Boolean = False); native;', @_Lape_Recorder_Run);
end.

