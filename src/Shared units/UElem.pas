unit UElem;

interface

uses
  UGlobal;

type
  TFrag = array [1 .. UGlobal.FragSize] of integer;

  TPRFrag = ^TRFrag;

  TRFrag = record
    frag: TFrag;
    count: int64;
  end;

function CompareFrag(f1, f2: TFrag): byte;

implementation

function CompareFrag(f1, f2: TFrag): byte;
var
  i: byte;
  r: byte;
begin
  r := 1;
  i := 1;
  while (f1[i] = f2[i]) and (i < UGlobal.FragSize) do
    i := i + 1;
  if f1[i] < f2[i] then
    r := 0;
  if f1[i] = f2[i] then
    r := 1;
  if f1[i] > f2[i] then
    r := 2;
  result := r;
end;

end.