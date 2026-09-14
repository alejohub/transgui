{*******************************************************************************
  Windows certificate-store integration for Transmission Remote GUI.
*******************************************************************************}

unit WindowsCertStore;

{$mode objfpc}{$H+}{$J-}

interface

uses
  ssl_openssl3;

function AddWindowsTrustedRoots(SSL: TSSLOpenSSL3; out ErrorMessage: string): Boolean;
function IsMissingOptionalSystemStoreError(ErrorCode: Cardinal): Boolean;

implementation

uses
  Windows, SysUtils, Crypt32;

const
  CertStoreOpenExistingFlag = $00004000;

type
  TCertificateList = array of AnsiString;

function IsMissingOptionalSystemStoreError(ErrorCode: Cardinal): Boolean;
begin
  Result := (ErrorCode = ERROR_FILE_NOT_FOUND) or (ErrorCode = CRYPT_E_NOT_FOUND);
end;

function IsEndOfCertificateEnumeration(ErrorCode: DWORD): Boolean;
begin
  Result := (ErrorCode = ERROR_SUCCESS) or (ErrorCode = CRYPT_E_NOT_FOUND) or
    (ErrorCode = ERROR_NO_MORE_FILES);
end;

function SystemStoreLocationName(Location: DWORD): string;
begin
  case Location of
    CERT_SYSTEM_STORE_CURRENT_USER:
      Result := 'CURRENT_USER';
    CERT_SYSTEM_STORE_LOCAL_MACHINE:
      Result := 'LOCAL_MACHINE';
  else
    Result := 'unknown location';
  end;
end;

function SystemStoreErrorMessage(const ApiName: string;
  const StoreName: UnicodeString; Location, ErrorCode: DWORD): string;
begin
  Result := Format('%s failed for Windows %s certificate store at %s (error %s): %s.',
    [ApiName, String(StoreName), SystemStoreLocationName(Location),
    IntToStr(Int64(ErrorCode)), SysErrorMessage(ErrorCode)]);
end;

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

function ReadSystemStore(const StoreName: UnicodeString; Location: DWORD;
  AllowMissing: Boolean; var Certificates: TCertificateList;
  out ErrorMessage: string): Boolean;
var
  Store: HCERTSTORE;
  Context: PCCERT_CONTEXT;
  Certificate: AnsiString;
  ErrorCode: DWORD;
begin
  Result := False;
  { CERT_STORE_PROV_SYSTEM_W is the numeric LPCSTR provider 10; its pvPara
    parameter is an LPCWSTR system-store name. }
  Store := CertOpenStore(CERT_STORE_PROV_SYSTEM_W, 0, 0,
    Location or CertStoreOpenExistingFlag or CERT_STORE_READONLY_FLAG,
    Pointer(PWideChar(StoreName)));
  if Store = 0 then
  begin
    ErrorCode := GetLastError;
    if AllowMissing and IsMissingOptionalSystemStoreError(ErrorCode) then
      Exit(True);
    ErrorMessage := SystemStoreErrorMessage('CertOpenStore(CERT_STORE_PROV_SYSTEM_W)',
      StoreName, Location, ErrorCode);
    Exit;
  end;
  try
    Context := nil;
    repeat
      SetLastError(ERROR_SUCCESS);
      Context := CertEnumCertificatesInStore(Store, Context);
      if Context = nil then
      begin
        ErrorCode := GetLastError;
        if IsEndOfCertificateEnumeration(ErrorCode) then
          Break;
        ErrorMessage := SystemStoreErrorMessage('CertEnumCertificatesInStore',
          StoreName, Location, ErrorCode);
        Exit;
      end;
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

  if not ReadSystemStore('Disallowed', CERT_SYSTEM_STORE_CURRENT_USER, True,
    Disallowed, ErrorMessage) then
    Exit;
  if not ReadSystemStore('Disallowed', CERT_SYSTEM_STORE_LOCAL_MACHINE, True,
    Disallowed, ErrorMessage) then
    Exit;
  if not ReadSystemStore('ROOT', CERT_SYSTEM_STORE_CURRENT_USER, False, Roots,
    ErrorMessage) then
    Exit;
  if not ReadSystemStore('ROOT', CERT_SYSTEM_STORE_LOCAL_MACHINE, False, Roots,
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
