{*******************************************************************************
  TLS configuration shared by the HTTPS clients.
*******************************************************************************}

unit TlsConfig;

{$mode objfpc}{$H+}{$J-}

interface

uses
  blcksock;

function InitializeTls(out ErrorMessage: string): Boolean;
function ConfigureTls(SSL: TCustomSSL; out ErrorMessage: string): Boolean;
function IsHttpsUrl(const URL: string): Boolean;

implementation

uses
  SysUtils, ssl_openssl3, ssl_openssl3_lib, WindowsCertStore;

function InitializeTls(out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  if not IsSSLloaded then
    if InitSSLInterface then
      SSLImplementation := TSSLOpenSSL3;
  Result := IsSSLloaded and (SSLImplementation = TSSLOpenSSL3);
  if not Result then
    ErrorMessage := 'OpenSSL could not be loaded.';
end;

function ConfigureTls(SSL: TCustomSSL; out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';
  if not (SSL is TSSLOpenSSL3) then
  begin
    ErrorMessage := 'OpenSSL TLS support is unavailable.';
    Exit;
  end;
  SSL.SSLType := LT_TLSv1_2_or_later;
  SSL.VerifyCert := True;
  Result := AddWindowsTrustedRoots(TSSLOpenSSL3(SSL), ErrorMessage);
end;

function IsHttpsUrl(const URL: string): Boolean;
begin
  Result := CompareText(Copy(Trim(URL), 1, Length('https://')), 'https://') = 0;
end;

end.
