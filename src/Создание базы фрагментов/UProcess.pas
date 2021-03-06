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
  MAX_BUFFER_SIZE = 15000000;

type
  TPRListElem = ^TRListElem;

  TRListElem = record
    elem: UElem.TRElem;
    prev, next: TPRListElem;
  end;

  TFrame = array [1 .. UGlobal.PicH, 1 .. UGlobal.PicW] of byte;

var
  FrameOld, FrameNew: TFrame;
  FrameData: array [1 .. UGlobal.PicH, 1 .. UGlobal.PicW] of integer;
  FrameBase: array [1 .. UGlobal.FrameBaseSize] of UElem.TRElem;
  BASE_COUNT: LongWord;
  elemBuffer: array [1 .. MAX_BUFFER_SIZE] of TPRElem;
  DLF, DLL: TPRListElem;

function GetPixelValue(i, j: integer): byte;
begin
  if i < 1 then
    i := 1;
  if i > UGlobal.PicH then
    i := UGlobal.PicH;
  if j < 1 then
    j := 1;
  if j > UGlobal.PicW then
    j := UGlobal.PicW;
  GetPixelValue := FrameNew[i, j];
end;

procedure AVG_Filter(h, w: word);
var
  i, j: word;
  fi, fj: integer;
  sum: LongWord;
  GSIR: TFrame;
begin
  for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
    begin
      sum := 0;
      for fi := -h to h do
        for fj := -w to w do
          sum := sum + GetPixelValue(i + fi, j + fj);
      GSIR[i, j] := round(sum / ((2 * h + 1) * (2 * w + 1)));
    end;
  FrameNew := GSIR;
  { for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
    FrameNew[i, j] := GSIR[i, j]; }
end;

procedure Median_Filter(h, w: word);
var
  i, j: word;
  fi, fj: integer;
  GSIR: array [1 .. UGlobal.PicH, 1 .. UGlobal.PicW] of byte;
  k, l: word;
  val: byte;
  tmp: array of byte;
begin
  SetLength(tmp, (2 * h + 1) * (2 * w + 1) + 1);
  for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
    begin
      k := 0;
      for fi := -h to h do
        for fj := -w to w do
        begin
          k := k + 1;
          tmp[k] := GetPixelValue(i + fi, j + fj);
        end;
      for k := 1 to (2 * h + 1) * (2 * w + 1) - 1 do
        for l := k + 1 to (2 * h + 1) * (2 * w + 1) do
          if tmp[k] > tmp[l] then
          begin
            val := tmp[k];
            tmp[k] := tmp[l];
            tmp[l] := val;
          end;
      GSIR[i, j] := tmp[((2 * h + 1) * (2 * w + 1) div 2) + 1];
    end;
  tmp := nil;
  for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
      FrameNew[i, j] := GSIR[i, j];
end;

procedure Thresold_Filter(Thresold: word);
var
  i, j: word;
begin
  for i := 1 to UGlobal.PicH do
    for j := 1 to UGlobal.PicW do
    begin
      if Abs(FrameOld[i, j] - FrameNew[i, j]) < Thresold then
        FrameNew[i, j] := FrameOld[i, j];
    end;
end;

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
      case BaseColor of
      RGB_R: FrameNew[i + 1, j + 1] := p[3 * j + 2];
      RGB_G: FrameNew[i + 1, j + 1] := p[3 * j + 1];
      RGB_B: FrameNew[i + 1, j + 1] := p[3 * j];
      YIQ_Y: FrameNew[i + 1, j + 1] := round(0.299 * p[3 * j + 2] + 0.587 * p[3 * j + 1] + 0.114 * p[3 * j]);
      YIQ_I: FrameNew[i + 1, j + 1] := round(0.596 * p[3 * j + 2] + 0.274 * p[3 * j + 1] + 0.321 * p[3 * j]);
      YIQ_Q: FrameNew[i + 1, j + 1] := round(0.211 * p[3 * j + 2] + 0.523 * p[3 * j + 1] + 0.311 * p[3 * j]);
      end;
      if UGlobal.GrayCode then
        FrameNew[i + 1, j + 1] := FrameNew[i + 1, j + 1] xor (FrameNew[i + 1, j + 1] shr 1);
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
      if BaseType = btMDiff then
        val := FrameNew[row, col] - FrameOld[row, col];
      if BaseType = btLDiff then
        val := FrameNew[row, col] xor FrameOld[row, col];
      if BaseType = btFrag then
        val := FrameNew[row, col];
      if BitNum = 9 then
      begin
        if val > 0 then
          val := 255
        else
          val := -255;
      end;
      if BitNum in [1 .. 8] then
      begin
        val := val and (1 shl (BitNum - 1));
        if val > 0 then
          val := 255
        else
          val := -255;
      end;
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
      if BitNum = 0 then
      begin
        if BaseType = btMDiff then
          val := 128 + (FrameData[i + 1, j + 1] div 2);
        if BaseType = btLDiff then
          val := FrameData[i + 1, j + 1];
        if BaseType = btFrag then
          val := FrameData[i + 1, j + 1];
      end;
      if BitNum in [1 .. 9] then
        val := FrameData[i + 1, j + 1];
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
      procedure sort(l, R: LongWord);
      var
        w, x: UElem.TRElem;
        i, j: LongWord;
      begin
        i := l;
        j := R;
        x := FrameBase[(l + R) div 2];
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
        if l < j then
          sort(l, j);
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
  procedure Qsort(l, R: LongWord);
  var
    w, x: UElem.TRElem;
    i, j: LongWord;
  begin
    i := l;
    j := R;
    x := elemBuffer[(l + R) div 2]^;
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
    if l < j then
      Qsort(l, j);
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
  procedure InsertBefore(elem: TPRListElem; newFrag: UElem.TRElem);
  var
    NewElem, tmp: TPRListElem;
  begin
    NEW(NewElem);
    NewElem^.elem := newFrag;
    tmp := elem^.prev;
    tmp^.next := NewElem;
    NewElem^.next := elem;
    elem^.prev := NewElem;
    NewElem^.prev := tmp;
  end;

var
  tmpFrag: TRElem;
  tmp: TPRListElem;
  i, k: LongWord;
begin
  Qsort(1, BASE_COUNT);
  k := 1;
  for i := 2 to BASE_COUNT do
  begin
    if UElem.CompareElem(elemBuffer[i]^.elem, elemBuffer[k]^.elem) = 1 then
      elemBuffer[k]^.count := elemBuffer[k]^.count + elemBuffer[i]^.count
    else
    begin
      k := k + 1;
      elemBuffer[k]^.elem := elemBuffer[i]^.elem;
      elemBuffer[k]^.count := elemBuffer[i]^.count;
    end;
    if i <> k then
      elemBuffer[i]^.count := 0;
  end;
  BASE_COUNT := k;
  tmp := DLF;
  i := 0;
  while i < BASE_COUNT do
  begin
    i := i + 1;
    tmpFrag := elemBuffer[i]^;
    while (tmp <> DLL) and (UElem.CompareElem(tmp^.elem.elem, tmpFrag.elem) = 0) do
      tmp := tmp^.next;
    begin
      if UElem.CompareElem(tmp^.elem.elem, tmpFrag.elem) = 1 then
        tmp^.elem.count := tmp^.elem.count + tmpFrag.count
      else
        InsertBefore(tmp, tmpFrag);
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
  case FilterType of
  ftNone:;
  ftAVG: AVG_Filter(FilterParam, FilterParam);
  ftMedian: Median_Filter(FilterParam, FilterParam);
  ftThresold: Thresold_Filter(FilterParam);
  end;
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

  FilterType := ftNone;
  FilterParam := 0;
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
  UStatList.WriteBaseInfo(USettings.BaseName + '.txt');
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
