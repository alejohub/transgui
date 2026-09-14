{*******************************************************************************
  Windows certificate-store integration for Transmission Remote GUI.
*******************************************************************************}

unit WindowsCertStore;

{$mode objfpc}{$H+}{$J-}

interface

uses
  ssl_openssl3;

function AddWindowsTrustedRoots(SSL: TSSLOpenSSL3; out ErrorMessage: string): Boolean;

implementation

uses
  Windows, SysUtils;

const
  CertStoreProvSystem = 10;
  CertSystemStoreCurrentUser = $00010000;
  CertSystemStoreLocalMachine = $00020000;
  CertStoreOpenExistingFlag = $00004000;
  CertStoreReadonlyFlag = $00008000;
  CryptENotFound: DWORD = $80092004;

type
  PTransGuiCertContext = ^TTransGuiCertContext;
  TTransGuiCertContext = packed record
    dwCertEncodingType: DWORD;
    pbCertEncoded: PByte;
    cbCertEncoded: DWORD;
    pCertInfo: Pointer;
    hCertStore: THandle;
  end;
  TCertificateList = array of AnsiString;

function CertOpenStore(lpszStoreProvider: PAnsiChar; dwMsgAndCertEncodingType: DWORD;
  hCryptProv: THandle; dwFlags: DWORD; pvPara: Pointer): THandle; stdcall;
  external 'crypt32.dll' name 'CertOpenStore';
function CertEnumCertificatesInStore(hCertStore: THandle;
  pPrevCertContext: PTransGuiCertContext): PTransGuiCertContext; stdcall;
  external 'crypt32.dll' name 'CertEnumCertificatesInStore';
function CertCloseStore(hCertStore: THandle; dwFlags: DWORD): BOOL; stdcall;
  external 'crypt32.dll' name 'CertCloseStore';

function ContainsCertificate(const Certificates: TCertificateList;
  const Certificate: AnsiString): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Certificates) do
    if Certificates[I] = Certificate then
      Exit(True);
  Result := False;
end;

procedure AddCertificate(var Certificates: TCertificateList;
  const Certificate: AnsiString);
begin
  if ContainsCertificate(Certificates, Certificate) then
    Exit;
  SetLength(Certificates, Length(Certificates) + 1);
  Certificates[High(Certificates)] := Certificate;
end;

function ReadSystemStore(const StoreName: AnsiString; Location: DWORD;
  AllowMissing: Boolean; var Certificates: TCertificateList;
  out ErrorMessage: string): Boolean;
var
  Store: THandle;
  Context: PTransGuiCertContext;
  Certificate: AnsiString;
begin
  Result := False;
  Store := CertOpenStore(PAnsiChar(PtrUInt(CertStoreProvSystem)), 0, 0,
    Location or CertStoreOpenExistingFlag or CertStoreReadonlyFlag,
    PAnsiChar(StoreName));
  if Store = 0 then
  begin
    if AllowMissing and (GetLastError = CryptENotFound) then
      Exit(True);
    ErrorMessage := Format('Unable to open the Windows %s certificate store: %s.',
      [String(StoreName), SysErrorMessage(GetLastError)]);
    Exit;
  end;
  try
    Context := nil;
    repeat
      Context := CertEnumCertificatesInStore(Store, Context);
      if Context = nil then
        Break;
      SetString(Certificate, PAnsiChar(Context^.pbCertEncoded), Context^.cbCertEncoded);
      AddCertificate(Certificates, Certificate);
    until False;
  finally
    CertCloseStore(Store, 0);
  end;
  Result := True;
end;

function AddWindowsTrustedRoots(SSL: TSSLOpenSSL3; out ErrorMessage: string): Boolean;
var
  Roots: TCertificateList;
  Disallowed: TCertificateList;
  I, Added: Integer;
begin
  Result := False;
  ErrorMessage := '';
  SetLength(Roots, 0);
  SetLength(Disallowed, 0);

  if not ReadSystemStore('Disallowed', CertSystemStoreCurrentUser, True,
    Disallowed, ErrorMessage) then
    Exit;
  if not ReadSystemStore('Disallowed', CertSystemStoreLocalMachine, True,
    Disallowed, ErrorMessage) then
    Exit;
  if not ReadSystemStore('ROOT', CertSystemStoreCurrentUser, True, Roots,
    ErrorMessage) then
    Exit;
  if not ReadSystemStore('ROOT', CertSystemStoreLocalMachine, True, Roots,
    ErrorMessage) then
    Exit;

  Added := 0;
  for I := 0 to High(Roots) do
    if not ContainsCertificate(Disallowed, Roots[I]) then
      if SSL.AddTrustedCertificate(Roots[I]) then
        Inc(Added);
  if Added = 0 then
  begin
    ErrorMessage := 'The Windows trusted-root certificate store is empty.';
    Exit;
  end;
  Result := True;
end;

end.
