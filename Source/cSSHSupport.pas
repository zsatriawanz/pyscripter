{-----------------------------------------------------------------------------
 Unit Name: cSSHSupport
 Author:    Kiriakos Vlahos
 Date:      20-Sep-2018
 Purpose:   Support classes for editing and running remote files
 History:
-----------------------------------------------------------------------------}

unit cSSHSupport;

interface

Uses
  System.SysUtils,
  System.Classes,
  cPyScripterSettings,
  SynRegExpr;

type

  TSSHServer = class(TBaseOptions)
  private
    fName : string;
    fHostName : string;
    fUserName : string;
    fPythonCommand : string;
  public
    constructor Create; override;
    procedure Assign(Source: TPersistent); override;
    function DefaultName : string;
  published
    property Name : string read fName write fName;
    property HostName : string read fHostName write fHostName;
    property UserName : string read fUserName write fUserName;
    property PythonCommand : string read fPythonCommand write fPythonCommand;
  end;

  TSSHServerItem = class(TCollectionItem)
  private
    fSSHServer : TSSHServer;
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property SSHServer : TSSHServer read fSSHServer write fSSHServer;
  end;

  TUnc = class
    class var UncRE: TRegExpr;
    class constructor Create;
    class destructor Destroy;
    class function Format(Server, FileName : string): string;
    class function Parse(Const Unc : string; out Server, FileName : string): boolean;
  end;

  function ServerFromName(ServerName: string): TSSHServer;
  function EditSSHServers : boolean;
  function SelectSSHServer : string;
  function EditSSHConfiguration(Item : TCollectionItem) : boolean;
  procedure FillSSHConfigNames(Strings: TStrings);


  // SCP
  function Scp(const FromFile, ToFile: string; out ErrorMsg: string): boolean;
  function ScpUpload(const ServerName, LocalFile, RemoteFile: string; out ErrorMsg: string): boolean;
  function ScpDownload(const ServerName, RemoteFile, LocalFile: string; out ErrorMsg: string): boolean;

Const
  SshCommandOptions = '-o PasswordAuthentication=no -o StrictHostKeyChecking=no';
Var
  ScpTimeout : integer = 30000; // 30 seconds
  SSHServers : TCollection;

implementation

uses
  System.Threading,
  Vcl.Forms,
  jclSysUtils,
  JvGnugettext,
  dlgCollectionEditor,
  dlgOptionsEditor,
  StringResources,
  frmCommandOutput;

{ TSSHConfig }

procedure TSSHServer.Assign(Source: TPersistent);
begin
  if Source is TSSHServer then with TSSHServer(Source) do begin
    Self.fName := Name;
    Self.fHostName := HostName;
    Self.UserName := UserName;
    Self.fPythonCommand := PythonCommand;
  end else
    inherited;
end;

constructor TSSHServer.Create;
begin
  inherited;
  PythonCommand := 'python';
end;

function TSSHServer.DefaultName: string;
begin
  Result := HostName;
  if UserName <> '' then
    Result := UserName + '@' + HostName;
end;

procedure TSSHServerItem.Assign(Source: TPersistent);
begin
  if Source is TSSHServerItem then with TSSHServerItem(Source) do
    Self.fSSHServer.Assign(TSSHServerItem(Source).SSHServer)
  else
    inherited;
end;

constructor TSSHServerItem.Create(Collection: TCollection);
begin
  inherited;
  fSSHServer := TSSHServer.Create;
end;

destructor TSSHServerItem.Destroy;
begin
  fSSHServer.Free;
  inherited;
end;

function TSSHServerItem.GetDisplayName: string;
begin
  if SSHServer.Name <> '' then
    Result := SSHServer.Name
  else
    Result := SSHServer.DefaultName;
end;

function EditSSHServers : boolean;
begin
  Result := EditCollection(SSHServers,
    TSSHServerItem, _('SSH Servers'), EditSSHConfiguration, 580);
end;

function SelectSSHServer : string;
Var
  Index : integer;
begin
  Result := '';
  if SelectFromCollection(SSHServers,
    TSSHServerItem, _('Select SSH Server'), EditSSHConfiguration, 580, Index)
  then
    Result := TSSHServerItem(SSHServers.Items[Index]).SSHServer.Name;
end;

function EditSSHConfiguration(Item : TCollectionItem) : boolean;
Var
  Categories : array of TOptionCategory;
begin
  SetLength(Categories, 1);
  with Categories[0] do begin
    DisplayName :='SSH';
    SetLength(Options, 4);
    Options[0].PropertyName := 'Name';
    Options[0].DisplayName := _('SSH Server name');
    Options[1].PropertyName := 'HostName';
    Options[1].DisplayName := _('Host name');
    Options[2].PropertyName := 'UserName';
    Options[2].DisplayName := _('User name');
    Options[3].PropertyName := 'PythonCommand';
    Options[3].DisplayName := _('Command to execute python');
  end;

  Result := InspectOptions((Item as TSSHServerItem).fSSHServer,
     Categories, _('Edit SSH Server'), 580, False);
end;


procedure FillSSHConfigNames(Strings: TStrings);
Var
  Item : TCollectionItem;
begin
   Strings.Clear;
   for Item in SSHServers do
     Strings.Add(TSSHServerItem(Item).DisplayName);
end;

function ServerFromName(ServerName: string): TSSHServer;
Var
  Item : TCollectionItem;
begin
  Result := nil;
  for Item in SSHServers do
    if TSSHServerItem(Item).SSHServer.Name = ServerName then
      Result := TSSHServerItem(Item).SSHServer;
end;

function Scp(const FromFile, ToFile: string; out ErrorMsg: string): Boolean;
Var
  Task : ITask;
  Command, Output: string;
  ExitCode : integer;
begin
  Command :=
    Format('scp %s %s %s',
    [SshCommandOptions, FromFile, ToFile]);

  Task := TTask.Create(procedure
  begin
    ExitCode := JclSysUtils.Execute(Command, Output);
  end);
  Task.Start;
  if not Task.Wait(ScpTimeout) then
  begin
    ErrorMsg := SScpOtherError;
    Exit(False);
  end;

  Result :=  ExitCode = 0;

  case ExitCode of
    0: ErrorMsg :=  '';
    4: ErrorMsg := SScpError4;
    5: ErrorMsg := SScpError5;
    else
      ErrorMsg := SScpOtherError;
  end;
end;

function ScpUpload(const ServerName, LocalFile, RemoteFile: string; out ErrorMsg: string): boolean;
Var
  SSHServer : TSSHServer;
begin
  SSHServer := ServerFromName(ServerName);
  if not Assigned(SSHServer) then begin
    ErrorMsg := Format(SSSHUnknownServer, [ServerName]);
    Exit(False);
  end;

  Result := scp(LocalFile, Format('%s:%s', [SSHServer.DefaultName, RemoteFile]), ErrorMsg);
end;

function ScpDownload(const ServerName, RemoteFile, LocalFile: string; out ErrorMsg: string): boolean;
Var
  SSHServer : TSSHServer;
begin
  SSHServer := ServerFromName(ServerName);
  if not Assigned(SSHServer) then begin
    ErrorMsg := Format(SSSHUnknownServer, [ServerName]);
    Exit(False);
  end;

  Result := scp(Format('%s:%s', [SSHServer.DefaultName, RemoteFile]), LocalFile, ErrorMsg);
end;

{ Unc }

class constructor TUnc.Create;
begin
  UNCRE := TRegExpr.Create;
  UncRE.Expression := '^\\\\([^\\]+)\\(.+)';
  UncRe.Compile;
end;

class destructor TUnc.Destroy;
begin
  UncRe.Free;
end;

class function TUnc.Format(Server, FileName: string): string;
begin
  Result := System.SysUtils.Format('\\%s\%s', [Server, FileName]);
end;

class function TUnc.Parse(const Unc: string; out Server,
  FileName: string): boolean;
begin
  Server := '';
  FileName := '';
  Result := UncRE.Exec(Unc);
  if Result then begin
    Server := UncRE.Match[1];
    FileName := UncRE.Match[2];
  end;
end;

initialization
  SSHServers := TCollection.Create(TSSHServerItem);
finalization
  SSHServers.Free;
end.