unit UProcess;

interface

uses
  Vcl.Graphics;

var
  BMIn, BMOut: TBitMap;
  FrameNum: LongWord;

procedure ProcessFrame;
function BaseFull: byte;
procedure WriteList;

implementation

uses
  UGlobal, UElem, SysUtils, Windows, UFMain, USettings, Classes, UStatList;

const
  MAX_BUFFER_SIZE = 150000000;

type
  TPRListElem = ^TRListElem;

  TRListElem = record
    elem: UElem.TRElem;
    prev, next: TPRListElem;
  end;

var
  FrameOld, FrameNew: array [1 .. UGlobal.PicH, 1 .. UGlobal.PicW] of byte;
  FrameData: array [1 .. UGlobal.PicH, 1 .. UGlobal.PicW] of integer;
  FrameBase: array [1 .. UGlobal.FrameBaseSize] of UElem.TRElem;
  BASE_COUNT: LongWord;
  elemBuffer: array [1 .. MAX_BUFFER_SIZE] of TPRElem;
  DLF, DLL: TPRListElem;

procedure LoadFrameFromBitMap;
var
  i, j: LongWord;
  p: pByteArray;
begin
  for i := 0 to UGlobal.PicH - 1 do
  begin
    p := BMIn.ScanLine[i];
    for j := 0 to UGlobal.PicW - 1 do
    begin
{$IF BaseColor=RGB_R}
      FrameNew[i + 1, j + 1] := p[3 * j + 2];
{$IFEND}
{$IF BaseColor=RGB_G}
      FrameNew[i + 1, j + 1] := p[3 * j + 1];
{$IFEND}
{$IF BaseColor=RGB_B}
      FrameNew[i + 1, j + 1] := p[3 * j];
{$IFEND}
{$IF BaseColor=YIQ_Y}
      FrameNew[i + 1, j + 1] := round(0.299 * p[3 * j + 2] + 0.587 * p[3 * j + 1] + 0.114 * p[3 * j]);
{$IFEND}
{$IF BaseColor=YIQ_I}
      FrameNew[i + 1, j + 1] := round(0.596 * p[3 * j + 2] + 0.274 * p[3 * j + 1] + 0.321 * p[3 * j]);
{$IFEND}
{$IF BaseColor=YIQ_Q}
      FrameNew[i + 1, j + 1] := round(0.211 * p[3 * j + 2] + 0.523 * p[3 * j + 1] + 0.311 * p[3 * j]);
{$IFEND}
    end;
  end;
end;

procedure CreateFrameData;
var
  row, col: word;
  val: integer;
begin
  for row := 1 to UGlobal.PicH do
    for col := 1 to UGlobal.PicW do
    begin
{$IF BaseType=btMDiff}
      val := FrameNew[row, col] - FrameOld[row, col];
{$IFEND}
{$IF BaseType=btLDiff}
      val := FrameNew[row, col] xor FrameOld[row, col];
{$IFEND}
{$IF BaseType=btFrag}
      val := FrameNew[row, col];
{$IFEND}
{$IF BitNum=9}
      if val > 0 then
        val := 255
      else
        val := -255;
{$IFEND}
{$IF BitNum in [1..8]}
      val := val and (1 shl (BitNum - 1));
      if val > 0 then
        val := 255
      else
        val := -255;
{$IFEND}
      FrameData[row, col] := val;
    end;
end;

procedure ShowResultFrame;
var
  i, j: LongWord;
  pr: pByteArray;
  val: byte;
begin
  for i := 0 to UGlobal.PicH - 1 do
  begin
    pr := BMOut.ScanLine[i];
    for j := 0 to UGlobal.PicW - 1 do
    begin
{$IF BitNum=0}
{$IF BaseType=btMDiff}
      val := 128 + (FrameData[i + 1, j + 1] div 2);
{$IFEND}
{$IF BaseType=btLDiff}
      val := FrameData[i + 1, j + 1];
{$IFEND}
{$IF BaseType=btFrag}
      val := FrameData[i + 1, j + 1];
{$IFEND}
{$IFEND}
{$IF BitNum in [1..9]}
      val := FrameData[i + 1, j + 1];
{$IFEND}
      pr[3 * j] := val;
      pr[3 * j + 1] := val;
      pr[3 * j + 2] := val;
    end;
  end;
  UFMain.FMain.Image1.Picture.Bitmap.Assign(BMOut);
end;

procedure CreateFrameBase;
  procedure SealFrameBase();
    procedure QuickSort;
      procedure sort(L, R: LongWord);
      var
        w, x: UElem.TRElem;
        i, j: LongWord;
      begin
        i := L;
        j := R;
        x := FrameBase[(L + R) div 2];
        repeat
          while UElem.CompareElem(FrameBase[i].elem, x.elem) = 0 do
            i := i + 1;
          while UElem.CompareElem(x.elem, FrameBase[j].elem) = 0 do
            j := j - 1;
          if i <= j then
          begin
            w := FrameBase[i];
            FrameBase[i] := FrameBase[j];
            FrameBase[j] := w;
            i := i + 1;
            j := j - 1;
          end;
        until i > j;
        if L < j then
          sort(L, j);
        if i < R then
          sort(i, R);
      end;

    begin
      sort(1, UGlobal.FrameBaseSize);
    end;

  var
    i, k: LongWord;
  begin
    QuickSort;
    k := 1;
    for i := 2 to UGlobal.FrameBaseSize do
    begin
      if UElem.CompareElem(FrameBase[i].elem, FrameBase[k].elem) = 1 then
        FrameBase[k].count := FrameBase[k].count + 1
      else
      begin
        k := k + 1;
        FrameBase[k].elem := FrameBase[i].elem;
        FrameBase[k].count := FrameBase[i].count;
      end;
      if i <> k then
        FrameBase[i].count := 0;
    end;
  end;

var
  row, col, i, j, p: word;
  k: LongWord;
begin
  row := 1;
  col := 1;
  k := 1;
  while row <= UGlobal.PicH - (UGlobal.ElemH - 1) do
  begin
    while col <= UGlobal.PicW - (UGlobal.ElemW - 1) do
    begin
      p := 1;
      for i := row to row + (UGlobal.ElemH - 1) do
        for j := col to col + (UGlobal.ElemW - 1) do
        begin
          FrameBase[k].elem[p] := FrameData[i, j];
          p := p + 1;
        end;
      FrameBase[k].count := 1;
      k := k + 1;
      col := col + UGlobal.ElemW;
    end;
    row := row + UGlobal.ElemH;
    col := 1;
  end;
  SealFrameBase;
end;

procedure DropToList;
  procedure Qsort(L, R: LongWord);
  var
    w, x: UElem.TRElem;
    i, j: LongWord;
  begin
    i := L;
    j := R;
    x := elemBuffer[(L + R) div 2]^;
    repeat
      while UElem.CompareElem(elemBuffer[i]^.elem, x.elem) = 0 do
        i := i + 1;
      while UElem.CompareElem(x.elem, elemBuffer[j]^.elem) = 0 do
        j := j - 1;
      if i <= j then
      begin
        w := elemBuffer[i]^;
        elemBuffer[i]^ := elemBuffer[j]^;
        elemBuffer[j]^ := w;
        i := i + 1;
        j := j - 1;
      end;
    until i > j;
    if L < j then
      Qsort(L, j);
    if i < R then
      Qsort(i, R);
  end;
  procedure InsertAfter(elem: TPRListElem; newFrag: UElem.TRElem);
  var
    NewElem, tmp: TPRListElem;
  begin
    NEW(NewElem);
    NewElem^.elem := newFrag;
    tmp := elem^.next;
    elem^.next := NewElem;
    NewElem^.next := tmp;
    tmp^.prev := NewElem;
    NewElem^.prev := elem;
  end;

var
  tmpFrag: TRElem;
  tmp: TPRListElem;
  i: LongWord;
begin
  Qsort(1, BASE_COUNT);
  tmp := DLF;
  i := 0;
  while i < BASE_COUNT do
  begin
    i := i + 1;
    tmpFrag := elemBuffer[i]^;
    while (tmp^.next <> DLL) and (UElem.CompareElem(tmp^.elem.elem, tmpFrag.elem) = 0) do
      tmp := tmp^.next;
    if UElem.CompareElem(tmp^.elem.elem, tmpFrag.elem) = 1 then
    begin
      while UElem.CompareElem(tmp^.elem.elem, tmpFrag.elem) = 1 do
      begin
        tmp^.elem.count := tmp^.elem.count + tmpFrag.count;
        i := i + 1;
        if elemBuffer[i] = nil then
          break;
        tmpFrag := elemBuffer[i]^;
      end;
      i := i - 1;
    end
    else
    begin
      InsertAfter(tmp, tmpFrag);
      tmp := tmp^.next;
    end;
  end;
  for i := 1 to MAX_BUFFER_SIZE do
  begin
    dispose(elemBuffer[i]);
    elemBuffer[i] := nil;
  end;
  BASE_COUNT := 0;
end;

procedure AddToBase;
var
  i: LongWord;
begin
  if BASE_COUNT + UGlobal.FrameBaseSize > MAX_BUFFER_SIZE then
    DropToList;
  i := 1;
  while (FrameBase[i].count > 0) and (i <= UGlobal.FrameBaseSize) do
  begin
    BASE_COUNT := BASE_COUNT + 1;
    elemBuffer[BASE_COUNT] := NEW(UElem.TPRElem);
    elemBuffer[BASE_COUNT]^.elem := FrameBase[i].elem;
    elemBuffer[BASE_COUNT]^.count := FrameBase[i].count;
    i := i + 1;
  end;
end;

procedure ProcessFrame;
begin
  FrameOld := FrameNew;
  LoadFrameFromBitMap;
  CreateFrameData;
  ShowResultFrame;
  CreateFrameBase;
  AddToBase;
  FrameNum := FrameNum + 1;
end;

procedure Init;
var
  i, j: LongWord;
begin
  FrameNum := 0;

  BASE_COUNT := 0;
  for i := 1 to MAX_BUFFER_SIZE do
  begin
    elemBuffer[i] := nil;
  end;

  for i := 1 to UGlobal.FrameBaseSize do
    FrameBase[i].count := 0;

  for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
    begin
      FrameNew[i, j] := 0;
      FrameOld[i, j] := 0;
      FrameData[i, j] := 0;
    end;

  NEW(DLF);
  NEW(DLL);
  DLF^.prev := nil;
  DLF^.next := DLL;
  for i := 1 to UGlobal.ElemSize do
    DLF^.elem.elem[i] := -300;
  DLL^.prev := DLF;
  DLL^.next := nil;
  for i := 1 to UGlobal.ElemSize do
    DLL^.elem.elem[i] := 300;

  BMIn := Vcl.Graphics.TBitMap.Create;
  BMIn.Width := UGlobal.PicW;
  BMIn.Height := UGlobal.PicH;
  BMIn.PixelFormat := pf24bit;

  BMOut := Vcl.Graphics.TBitMap.Create;
  BMOut.Width := UGlobal.PicW;
  BMOut.Height := UGlobal.PicH;
  BMOut.PixelFormat := pf24bit;
end;

procedure WriteList;
var
  FileName: string;
  FS: TFIleStream;
  elem: TPRListElem;
begin
  DropToList;
  FileName := USettings.BaseName;
  FS := TFIleStream.Create(string(FileName + '.base'), fmCreate);

  elem := DLF^.next;
  while elem <> DLL do
  begin
    FS.Write(elem^.elem, SizeOf(UElem.TRElem));
    UStatList.AddID(elem^.elem.count);
    elem := elem^.next;
  end;
  UStatList.WriteBaseInfo(USettings.BaseName+'.txt');
  FS.Free;
end;

function BaseFull: byte;
begin
  BaseFull := round(BASE_COUNT / MAX_BUFFER_SIZE * 100);
end;

initialization

Init;

finalization

BMIn.Free;
BMOut.Free;

end.
