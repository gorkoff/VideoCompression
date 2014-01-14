unit USettings;

interface

type
  TBaseColor = (RGB_R, RGB_G, RGB_B, YIQ_Y, YIQ_I, YIQ_Q);
  TBaseType = (btFrag, btLDiff, btMDiff);

const
  BaseType = btFrag;
  BitNum = 0;

var
  FileName: string;
  BaseColor: TBaseColor;

implementation

end.
