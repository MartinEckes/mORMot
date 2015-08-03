unit dddToolsAdminMain;

{$I Synopse.inc} // define HASINLINE USETYPEINFO CPU32 CPU64 OWNNORMTOUPPER

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, mORMotUI, mORMotUILogin, mORMotToolbar, SynTaskDialog,
  SynCommons, mORMot, mORMotHttpClient,
  mORMotDDD, dddInfraApps,
  dddToolsAdminDB, dddToolsAdminLog;

type
  TAdminMainForm = class(TForm)
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
  protected
    fClient: TSQLHttpClientWebsockets;
    fAdmin: IAdministratedDaemon;
    fDatabases: TRawUTF8DynArray;
    fPage: TSynPager;
    fPages: array of TSynPage;
    fLogFrame: TLogFrame;
    fDBFrame: array of TDBFrame;
    fDefinition: TAdministratedDaemonClientDefinition;
  public
    LogFrameClass: TLogFrameClass;
    DBFrameClass: TDBFrameClass;
    function Open(const Definition: TAdministratedDaemonClientDefinition): Boolean;
  end;

var
  AdminMainForm: TAdminMainForm;

function ValidateDefinition(var Definition: TAdministratedDaemonClientDefinition): boolean;


implementation

{$R *.dfm}

function ValidateDefinition(var Definition: TAdministratedDaemonClientDefinition): boolean;
var U,P: string;
begin
  result := false;
  if Definition.Port='' then
    exit;
  if Definition.Server='' then
    Definition.Server := 'localhost';
  if Definition.UserName='' then
    if TLoginForm.Login(Application.Mainform.Caption,Format('Credentials for %s:%s',
        [Definition.Server,Definition.Port]),U,P,true,'') then begin
      Definition.UserName := StringToUTF8(U);
      Definition.HashedPassword := TSQLAuthUser.ComputeHashedPassword(StringToUTF8(P));
    end else
      exit;
  result := true;
end;

function TAdminMainForm.Open(const Definition: TAdministratedDaemonClientDefinition): boolean;
var temp: TForm;
    version: Variant;
begin
  result := true;
  if Assigned(fAdmin) then
    exit;
  try
    temp := CreateTempForm(Format('Connecting to %s:%s...',[Definition.Server,Definition.Port]));
    try
      Application.ProcessMessages;
      fClient := AdministratedDaemonClient(Definition);
      fClient.Services.Resolve(IAdministratedDaemon,fAdmin);
      version := _JsonFast(fAdmin.DatabaseExecute('','#version'));
      Caption := Format('%s - %s %s via %s:%s',[ExeVersion.ProgramName,
        version.prog,version.version,Definition.Server,Definition.Port]);
      fDefinition := Definition;
    finally
      temp.Free;
    end;
  except
    on E: Exception do begin
      ShowException(E);
      FreeAndNil(fClient);
      result := false;
    end;
  end;
end;

procedure TAdminMainForm.FormShow(Sender: TObject);
var i,n: integer;
begin
  if (fClient=nil) or (fAdmin=nil) or (fPage<>nil) then begin
    Close;
    exit;
  end;
  if LogFrameClass=nil then
    LogFrameClass := TLogFrame;
  if DBFrameClass=nil then
    DBFrameClass := TDBFrame;
  fDatabases := fAdmin.DatabaseList;
  fPage := TSynPager.Create(self);
  fPage.ControlStyle := fPage.ControlStyle+[csClickEvents]; // enable OnDblClick
  fPage.Parent := self;
  fPage.Align := alClient;
  n := length(fDatabases);
  SetLength(fPages,n+1);
  fPages[0] := TSynPage.Create(self);
  fPages[0].Caption := 'log';
  fPages[0].PageControl := fPage;
  fLogFrame := LogFrameClass.Create(fPages[0]);
  fLogFrame.Parent := fPages[0];
  fLogFrame.Align := alClient;
  fLogFrame.Admin := fAdmin;
  if n>0 then begin
    SetLength(fDBFrame,n);
    for i := 0 to n-1 do begin
      fPages[i+1] := TSynPage.Create(self);
      fPages[i+1].Caption := UTF8ToString(fDatabases[i]);
      fPages[i+1].PageControl := fPage;
      fDBFrame[i] := DBFrameClass.Create(fPages[i+1]);
      with fDBFrame[i] do begin
        Parent := fPages[i+1];
        Align := alClient;
        DatabaseName := fDatabases[i];
        Admin := fAdmin;
        Open;
      end;
    end;
    fPage.ActivePageIndex := 1;
    Application.ProcessMessages;
    fDBFrame[0].mmoSQL.SetFocus;
  end;
end;

procedure TAdminMainForm.FormDestroy(Sender: TObject);
var i: integer;
begin
  if  fLogFrame<>nil then begin
    if fLogFrame.Callback<>nil then
      fClient.Services.CallBackUnRegister(fLogFrame.Callback);
    fLogFrame.Closing;
  end;
  for i := 0 to high(fDBFrame) do
    fDBFrame[i].Admin := nil;
  fAdmin := nil;
  FreeAndNil(fClient);
end;

procedure TAdminMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var pageIndex: integer;
begin
  pageIndex := fPage.ActivePageIndex;
  if pageIndex=0 then // log keys
    case Key of
    VK_F3:
      fLogFrame.btnSearchNextClick(fLogFrame.btnSearchNext);
    ord('A')..ord('Z'),Ord('0')..ord('9'),32:
      if (shift=[]) and not fLogFrame.edtSearch.Focused then
        fLogFrame.edtSearch.Text := fLogFrame.edtSearch.Text+string(Char(Key)) else
      if (key=ord('F')) and (ssCtrl in Shift) then begin
        fLogFrame.edtSearch.SelectAll;
        fLogFrame.edtSearch.SetFocus;
      end;
    end else
  if pageIndex<=Length(fDBFrame) then
    with fDBFrame[pageIndex-1] do
    case Key of
    VK_RETURN:
    if (shift=[]) and (mmoSQL.SelLength=0) then begin
      btnExecClick(nil);
      Key := 0;
    end;
    VK_F9:
      btnExecClick(btnExec);
    ord('A'):
      if ssCtrl in Shift then begin
        mmoSQL.SelectAll;
        mmoSQL.SetFocus;
      end;
    ord('H'):
      if ssCtrl in Shift then
        btnHistoryClick(btnHistory);
    end;
end;

procedure TAdminMainForm.FormCreate(Sender: TObject);
begin
  DefaultFont.Name := 'Tahoma';
  DefaultFont.Size := 9;
  Caption := Format('%s %s',[ExeVersion.ProgramName,ExeVersion.Version.Detailed]);
end;

end.
