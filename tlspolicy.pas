{*******************************************************************************
  Human-readable errors for TLS certificate verification failures.
*******************************************************************************}

unit TlsPolicy;

{$mode objfpc}{$H+}{$J-}

interface

function TlsVerificationErrorMessage(VerifyError: Integer;
  const Fallback: string): string;

implementation

uses
  ssl_openssl3_lib;

function TlsVerificationErrorMessage(VerifyError: Integer;
  const Fallback: string): string;
begin
  case VerifyError of
    X509_V_ERR_CERT_NOT_YET_VALID, X509_V_ERR_CERT_HAS_EXPIRED,
    X509_V_ERR_ERROR_IN_CERT_NOT_BEFORE_FIELD,
    X509_V_ERR_ERROR_IN_CERT_NOT_AFTER_FIELD:
      Result := 'The server TLS certificate is expired or not yet valid.';
    X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT,
    X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN,
    X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY,
    X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE,
    X509_V_ERR_CERT_UNTRUSTED,
    X509_V_ERR_CERT_REJECTED:
      Result := 'The server TLS certificate is not trusted by Windows.';
    X509_V_ERR_HOSTNAME_MISMATCH, X509_V_ERR_IP_ADDRESS_MISMATCH:
      Result := 'The server TLS certificate does not match the configured host.';
  else
    Result := Fallback;
    if Result = '' then
      Result := 'The TLS connection could not be verified.';
  end;
end;

end.
