## SimbaRecorder

Install using Simba's package manager.

```pascal
procedure TRecorder.Start(Seconds: Integer; Directory: String); overload; // record currently targeted window
procedure TRecorder.Start(Window: PtrUInt; Seconds: Integer; Directory: String); // record a window handle
```

### Usage

```pascal
{$i recorder/recorder.simba}

begin
  Recorder.Start(15, 'DirectoryForVideos'); 
  
  Sleep(20000); // Continue running your script ...
end.
```

In this example above, whenever the script is terminated you would have a video recording of the last 15 seconds.
This is similar in concept to Nvidia's Shadowplay.

Video recording will be saved in `DirectoryForVideos` directory under the name `recording.mp4`.

Inspired by https://villavu.com/forum/showthread.php?t=118373

---

Notes: 
  - `Recorder.Start` runs another Simba script in the background which handles the recording and terminates when the parent script does.
  - FFmpeg binary included is ~75mb. So the release is quite big.
  - Windows only for now. But future platforms can easily be supported as FFMPEG & LZ4 are available.
