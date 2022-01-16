unit lz4;

// MSYS64

// pacman -S mingw-w64-i686-toolchain
// pacman -S mingw-w64-i686-lz4

// pacman -S mingw-w64-x86_64-toolchain
// pacman -S mingw-w64-x86_64-lz4

{$IFDEF WIN32}
  {$LINKLIB C:\msys64\mingw32\lib\liblz4}
  {$LINKLIB C:\msys64\mingw32\lib\gcc\i686-w64-mingw32\11.2.0\libgcc}
  {$LINKLIB C:\msys64\mingw32\i686-w64-mingw32\lib\libmsvcrt}
{$ENDIF}

{$IFDEF WIN64}
  {$LINKLIB C:\msys64\mingw64\lib\liblz4}
  {$LINKLIB C:\msys64\mingw64\lib\gcc\x86_64-w64-mingw32\11.2.0\libgcc}
  {$LINKLIB C:\msys64\mingw64\x86_64-w64-mingw32\lib\libmsvcrt}
{$ENDIF}

interface

function LZ4_compress_default(const src, dest: Pointer; const srcSize, destCapactiy: Integer): Integer; cdecl; external;
function LZ4_decompress_safe(const src, dest: Pointer; const compressedSize, destCapacity: Integer): Integer; cdecl; external;
function LZ4_compressBound(const inputSize: Integer): Integer; cdecl; external;

implementation

end.

