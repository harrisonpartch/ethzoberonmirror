MODULE OdAuth;
(* WebDAV, Copyright 2003, Edgar Schwarz.
Author.    Edgar Schwarz, edgar@edgarschwarz.de, (es)
Contents. An  object for allowing a simple version of Basic HTTP Authentication RFC 2617.
Contents. Access is controlled for collections only. Reading is allowed for all users without authentication.
Contents. For writing methods like PUT, PROPPATCH, DELETE, MKCOL, CHECKIN, ... an authentication header
Contents. is necessary.
Remarks.  Example call at EOF.
*)
IMPORT OdAuthBase, Commands, Streams;


PROCEDURE SetBasicRealm*(context: Commands.Context); (* host realm path. *)
(* Path could be used with host later to discriminate between different auth objects. *)
CONST
	Usage = "WebDAVAuth.SetBasicRealm <host> <realm> <path>.";
VAR
	host: ARRAY 64 OF CHAR;
	realm, path: ARRAY 128 OF CHAR;
	arg: Streams.Reader;
BEGIN
	arg := context.arg;
	arg.String( host );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	arg.String( realm );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	arg.String( path );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	OdAuthBase.SetBasicRealm(host, realm, path);
END SetBasicRealm;

PROCEDURE SetBasicAuth* ( context: Commands.Context ); (* host realm user password. *)
(* Path could be used with host later to discriminate between different auth objects. *)
CONST
	Usage = "WebDAVAuth.SetBasicAuth <host> <realm> <user> <password>.";
VAR
	host: ARRAY 64 OF CHAR;
	realm, user, password: ARRAY 128 OF CHAR;
	arg: Streams.Reader;
BEGIN
	arg := context.arg;
	arg.String( host );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	arg.String( realm );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	arg.String( user );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	arg.String( password );
	IF arg.res # 0 THEN context.out.String( Usage ); context.out.Ln; RETURN; END;

	OdAuthBase.SetBasicAuth (host, realm, user, password);
END SetBasicAuth;

PROCEDURE SetDefaultHost* ( context: Commands.Context ); (* host *)
(* Path could be used with host later to discriminate between different auth objects. *)
VAR
	host: ARRAY 64 OF CHAR;
	arg: Streams.Reader;
BEGIN
	arg := context.arg;
	arg.String( host );

	IF arg.res = 0 THEN
		COPY(host, OdAuthBase.defaultAuth.host);
	END;
END SetDefaultHost;

(* TODO: save users and passwords encrypted. *)

BEGIN
END OdAuth.

!WebDAVAuth.SetDefaultHost webdav.ethz.ch ! Not used yet
! Set realms, their paths and their users and passwords. The leading parameter "" means to take the default host.
WebDAVAuth.SetBasicRealm "" admin "/" 						! host realm path
WebDAVAuth.SetBasicAuth "" admin edgar <password>   ! host realm user, password
! Set request header: Authorization: Basic Base64("<user>:<password>")
WebDAVClient.SetBasicAuth "<user>:<password>"
