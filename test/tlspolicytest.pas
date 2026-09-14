{*******************************************************************************
  Offline tests for TLS certificate-verification error reporting.
*******************************************************************************}

unit TlsPolicyTest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTlsPolicyTestCase = class(TTestCase)
  published
    procedure ReportsHostNameMismatch;
    procedure ReportsUntrustedCertificate;
    procedure ReportsExpiredCertificate;
    procedure KeepsNetworkErrorFallback;
  end;

implementation

uses
  TlsPolicy, ssl_openssl3_lib;

procedure TTlsPolicyTestCase.ReportsHostNameMismatch;
begin
  AssertEquals('The server TLS certificate does not match the configured host.',
    TlsVerificationErrorMessage(X509_V_ERR_HOSTNAME_MISMATCH, 'ignored'));
  AssertEquals('The server TLS certificate does not match the configured host.',
    TlsVerificationErrorMessage(X509_V_ERR_IP_ADDRESS_MISMATCH, 'ignored'));
end;

procedure TTlsPolicyTestCase.ReportsUntrustedCertificate;
begin
  AssertEquals('The server TLS certificate is not trusted by Windows.',
    TlsVerificationErrorMessage(X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN, 'ignored'));
end;

procedure TTlsPolicyTestCase.ReportsExpiredCertificate;
begin
  AssertEquals('The server TLS certificate is expired or not yet valid.',
    TlsVerificationErrorMessage(X509_V_ERR_CERT_HAS_EXPIRED, 'ignored'));
end;

procedure TTlsPolicyTestCase.KeepsNetworkErrorFallback;
begin
  AssertEquals('Connection timed out.',
    TlsVerificationErrorMessage(0, 'Connection timed out.'));
end;

initialization
  RegisterTest(TTlsPolicyTestCase);

end.
