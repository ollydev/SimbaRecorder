unit recorder;

{$mode ObjFPC}{$H+}

interface

uses
  classes, sysutils, syncobjs, intfgraphics, graphtype, fileutil, process;

type
  TRecorder = class;

  TCompressedFrames = record
    Buffer: Pointer;
    BufferSize: Integer;
    CompressedSize: Integer;
  end;
  PCompressedFrames = ^TCompressedFrames;

  TCompressedFramesArray = array of TCompressedFrames;

  TCompressThread = class(TThread)
  public
    FRecorder: TRecorder;

    FData: PByte;
    FDataSize: SizeInt;
    FCompressing: Boolean;
    FCompressingTime: UInt64;

    FCompressedFrames: PCompressedFrames;
    FCompressEvent: TSimpleEvent;

    FCompressBufferSize: SizeInt;
    FCompressBuffer: PByte;

    procedure Execute; override;
  public
    constructor Create(Recorder: TRecorder); reintroduce;
    destructor Destroy; override;
  end;

  PRecorder = ^TRecorder;
  PRecorderGetFrame = ^TRecorderGetFrame;
  PRecorderGetTerminated = ^TRecorderGetTerminated;

  TRecorderGetFrame = function(Sender: TRecorder): Pointer;
  TRecorderGetTerminated = function(Sender: TRecorder): Boolean;

  TRecorder = class
  public
  const
    FPS = 15;
    FRAME_COMPRESS_COUNT = 10; // Compress 10 frames at a time
  protected
    FFMPEGPath: String;

    FFrameWidth, FFrameHeight: Integer;
    FFrameSize: Integer;

    FRawFrameIndex: Integer;
    FRawFrames: PByte;
    FRawFramesSize: SizeInt;
    FRawFramesBackBuffer: PByte;

    FCompressedFrames: TCompressedFramesArray;
    FCompressThread: TCompressThread;

    FGetFrame: TRecorderGetFrame;
    FGetTerminated: TRecorderGetTerminated;

    FDirectory: String;
    FDebugging: Boolean;

    procedure Debug(S: String; Args: array of const);
    procedure Error(S: String; Args: array of const);

    procedure AddFrame(const Data: PByte);
    procedure GenerateVideo;
  public
    constructor Create(Seconds: Integer; Directory: String; Width, Height: Integer; GetFrameFunc: TRecorderGetFrame; GetTerminatedFunc: TRecorderGetTerminated);
    destructor Destroy; override;

    procedure Run(Debugging: Boolean = False);

    property FFMPEG: String read FFMPEGPath write FFMPEGPath;
  end;

implementation

uses
  FPImage, FPWritePNG, ZStream, lz4;

const
  ONE_MB = 1024 * 1024;

function IntToMB(const Bytes: Integer): String;
begin
  Result := Format('%f', [Bytes / ONE_MB]) + 'mb';
end;

procedure Swap(var A, B: Pointer); inline;
var
  T: Pointer;
begin
  T := A;
  A := B;
  B := T;
end;

procedure ShiftUp(var CompressedFrames: TCompressedFramesArray); inline;
var
  Temp: TCompressedFrames;
begin
  Temp := CompressedFrames[High(CompressedFrames)];
  Temp.CompressedSize := 0;

  Move(CompressedFrames[0], CompressedFrames[1], High(CompressedFrames) * SizeOf(TCompressedFrames));

  CompressedFrames[0] := Temp;
end;

procedure TCompressThread.Execute;
begin
  try
    while (not Terminated) do
    begin
      if (FCompressEvent.WaitFor(1000) = wrSignaled) then
        with FCompressedFrames^ do
        begin
          FCompressing := True;
          FCompressingTime := GetTickCount64();

          CompressedSize := LZ4_compress_default(FData, FCompressBuffer, FDataSize, FCompressBufferSize);
          if (CompressedSize <= 0) then
            FRecorder.Error('Compress error: %d', [CompressedSize])
          else
          begin
            if FRecorder.FDebugging then
              FRecorder.Debug('Compressed %s to %s in %dms', [IntToMB(FCompressBufferSize), IntToMB(CompressedSize), GetTickCount64() - FCompressingTime]);

            if (BufferSize < CompressedSize) then
            begin
              BufferSize := CompressedSize + ONE_MB;

              ReAllocMem(Buffer, BufferSize);
            end;

            Move(FCompressBuffer^, Buffer^, CompressedSize);
          end;

          FCompressing := False;
        end;

      FCompressEvent.ResetEvent();
    end;
  except
    on E: Exception do
    begin
      FRecorder.Error(E.Message, []);

      raise;
    end;
  end;
end;

constructor TCompressThread.Create(Recorder: TRecorder);
begin
  inherited Create(False);

  FreeOnTerminate := True;

  FRecorder := Recorder;
  FDataSize := FRecorder.FRawFramesSize;

  FCompressBufferSize := LZ4_compressBound(FDataSize) + ONE_MB;
  FCompressBuffer := GetMem(FCompressBufferSize);

  FCompressEvent := TSimpleEvent.Create();
end;

destructor TCompressThread.Destroy;
begin
  if (FCompressEvent <> nil) then
    FCompressEvent.Free();
  FreeMem(FCompressBuffer);

  inherited Destroy();
end;

procedure TRecorder.Debug(S: String; Args: array of const);
begin
  try
    WriteLn('[Recorder]: ' + Format(S, Args));
  except
  end;
end;

procedure TRecorder.Error(S: String; Args: array of const);

  procedure AppendFile(const FileName, S: String);
  var
    Attempts: Integer;
    Handle: THandle;
  begin
    if (Length(S) = 0) then
      Exit;

    Attempts := 0;
    while (Attempts < 5) do
    begin
      Inc(Attempts);

      if not FileExists(FileName) then
        Handle := FileCreate(FileName, fmOpenReadWrite or fmShareDenyWrite)
      else
        Handle := FileOpen(FileName, fmOpenReadWrite or fmShareDenyWrite);

      if (Handle > 0) then
      begin
        FileSeek(Handle, 0, fsFromEnd);
        FileWrite(Handle, S[1], Length(S));
        FileClose(Handle);

        Exit;
      end else
        Sleep(50);
    end;
  end;

begin
  S := Format(S, Args) + LineEnding;

  try
    WriteLn('[Recorder]: ' + S);
  except
  end;

  AppendFile(FDirectory + 'log.txt', S);
end;

procedure TRecorder.AddFrame(const Data: PByte);

  function GetRamUsage: Integer;
  var
    I: Integer;
  begin
    Result := MemSize(FRawFrames) + MemSize(FRawFramesBackBuffer) + MemSize(FCompressThread.FCompressBuffer);
    for I := 0 to High(FCompressedFrames) do
      Result += FCompressedFrames[I].BufferSize;
  end;

begin
  Move(Data^, FRawFrames[FRawFrameIndex * FFrameSize], FFrameSize);

  Inc(FRawFrameIndex);
  if (FRawFrameIndex = FRAME_COMPRESS_COUNT) then
  begin
    if not FCompressThread.FCompressing then
    begin
      if FDebugging then
        Debug('Memory usage: %s', [IntToMB(GetRamUsage())]);

      // Drop last frame index (shift to start)
      ShiftUp(FCompressedFrames);
      // Swap buffer so new frames don't get compressed
      Swap(FRawFrames, FRawFramesBackBuffer);

      FCompressThread.FData := FRawFramesBackBuffer;
      FCompressThread.FCompressedFrames := @FCompressedFrames[0];
      FCompressThread.FCompressEvent.SetEvent();
    end else
      Debug('Dropping frames (still compressing)', []);

    FRawFrameIndex := 0;
  end;
end;

procedure TRecorder.GenerateVideo;
var
  ImageWriter: TFPWriterPNG;

  function MakeFile(Name: String; CreateDir, CreateFile: Boolean): String;
  var
    I: Integer = 0;
  begin
    Result := FDirectory + Format(Name, [0]);

    while DirectoryExists(Result) or FileExists(Result) do
    begin
      Inc(I);
      Result := FDirectory + Format(Name, [I]);
    end;

    if CreateDir then ForceDirectories(Result);
    if CreateFile then FileClose(FileCreate(Result));
  end;

  procedure Save(Image: TLazIntfImage; FrameDirectory: String; FrameIndex: Integer; Frame: PByte; FrameSize: Integer);
  begin
    Move(Frame^, Image.PixelData^, FrameSize);

    Image.SaveToFile(FrameDirectory + IntToStr(FrameIndex) + '.png', ImageWriter);
  end;

var
  Image: TLazIntfImage;
  RawImage: TRawImage;
  I, J, FrameIndex: Integer;
  Size: Integer;
  Output, FileName, FrameDirectory: String;
begin
  FrameIndex := 0;
  FrameDirectory := IncludeTrailingPathDelimiter(MakeFile('frames_%d', True, False));

  RawImage := Default(TRawImage);
  RawImage.Description.Init_BPP32_B8G8R8_BIO_TTB(FFrameWidth, FFrameHeight);
  RawImage.CreateData(True);

  ImageWriter := TFPWriterPNG.Create();
  ImageWriter.CompressionLevel := clfastest;

  Image := TLazIntfImage.Create(RawImage, False);
  try
    for I := High(FCompressedFrames) downto 0 do
      with FCompressedFrames[I] do
      begin
        if (CompressedSize = 0) then
          Continue;

        Size := LZ4_decompress_safe(Buffer, FRawFrames, CompressedSize, FRawFramesSize);
        if (Size <= 0) then
        begin
          Error('Decompress error: %d', [Size]);
          Continue;
        end;

        for J := 0 to (Size div FFrameSize) - 1 do
        begin
          Save(Image, FrameDirectory, FrameIndex, @FRawFrames[J * FFrameSize], FFrameSize);

          Inc(FrameIndex);
        end;
      end;

    FileName := MakeFile('recording_%d.mp4', False, True);

    if (not RunCommand(FFMPEGPath, ['-y', '-framerate', IntToStr(FPS), '-f', 'image2' ,'-i', FrameDirectory + '%d.png', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2', '-vcodec', 'libx264', '-crf', '25', '-pix_fmt', 'yuv420p', FileName], Output, [poStderrToOutPut])) then
      Error(Output, []);
  finally
    DeleteDirectory(FrameDirectory, False);

    if (ImageWriter <> nil) then
      ImageWriter.Free();
    if (Image <> nil) then
      Image.Free();
  end;

  RawImage.FreeData();
end;

procedure TRecorder.Run(Debugging: Boolean);

  procedure Idle(const TimeUsed: Int64);
  var
    IdleTime: Int64;
  begin
    IdleTime := (1000 div FPS) - TimeUsed;

    if (IdleTime > 0) then
      Sleep(IdleTime)
    else
      Debug('Dropping frames (GetFrame took %dms)', [TimeUsed]);
  end;

var
  TimeUsed: Int64;
begin
  FDebugging := Debugging;
  FCompressThread := TCompressThread.Create(Self);

  try
    while True do
    begin
      if (FRawFrameIndex = 0) and FGetTerminated(Self) then
        Break;

      TimeUsed := GetTickCount64();
      AddFrame(FGetFrame(Self));
      TimeUsed := GetTickCount64() - TimeUsed;

      Idle(TimeUsed);
    end;

    FCompressThread.Terminate();
    FCompressThread.WaitFor();

    GenerateVideo();
  except
    on E: Exception do
    begin
      Error(E.Message, []);

      raise;
    end;
  end;
end;

constructor TRecorder.Create(Seconds: Integer; Directory: String; Width, Height: Integer; GetFrameFunc: TRecorderGetFrame; GetTerminatedFunc: TRecorderGetTerminated);
begin
  inherited Create();

  FFMPEG := 'ffmpeg.exe';
  FDirectory := IncludeTrailingPathDelimiter(ExpandFileName(Directory));
  if not DirectoryExists(FDirectory) then
    ForceDirectories(FDirectory);

  Debug('Saving to %s', [FDirectory]);

  FFrameWidth := Width;
  FFrameHeight := Height;
  FFrameSize := (Width * Height) * 4;

  FGetFrame := GetFrameFunc;
  FGetTerminated := GetTerminatedFunc;

  FRawFrameIndex := 0;
  FRawFramesSize := FRAME_COMPRESS_COUNT * FFrameSize;
  FRawFrames := GetMem(FRawFramesSize);
  FRawFramesBackBuffer := GetMem(FRawFramesSize);

  SetLength(FCompressedFrames, (Seconds * FPS) div FRAME_COMPRESS_COUNT);
end;

destructor TRecorder.Destroy;
var
  I: Integer;
begin
  FreeMem(FRawFrames);
  FreeMem(FRawFramesBackBuffer);
  for I := 0 to High(FCompressedFrames) do
    FreeMem(FCompressedFrames[I].Buffer);

  inherited Destroy();
end;

end.

