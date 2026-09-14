{*******************************************************************************
  Tests for Windows certificate-store error handling and root enumeration.
*******************************************************************************}

unit WindowsCertStoreTest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TWindowsCertStoreTestCase = class(TTestCase)
  published
    procedure AcceptsMissingOptionalStore;
    procedure RejectsOtherStoreErrors;
    procedure LoadsWindowsRootCertificates;
  end;

implementation

uses
  Windows, WindowsCertStore, ssl_openssl3;

const
  CryptENotFound: Cardinal = $80092004;

procedure TWindowsCertStoreTestCase.AcceptsMissingOptionalStore;
begin
  AssertTrue(IsMissingOptionalSystemStoreError(ERROR_FILE_NOT_FOUND));
  AssertTrue(IsMissingOptionalSystemStoreError(CryptENotFound));
end;

procedure TWindowsCertStoreTestCase.RejectsOtherStoreErrors;
begin
  AssertFalse(IsMissingOptionalSystemStoreError(ERROR_ACCESS_DENIED));
end;

procedure TWindowsCertStoreTestCase.LoadsWindowsRootCertificates;
var
  SSL: TSSLOpenSSL3;
  ErrorMessage: string;
begin
  ErrorMessage := '';
  SSL := TSSLOpenSSL3.Create(nil);
  try
    AssertTrue(ErrorMessage, AddWindowsTrustedRoots(SSL, ErrorMessage));
  finally
    SSL.Free;
  end;
end;

initialization
  RegisterTest(TWindowsCertStoreTestCase);

end.
