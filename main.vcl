backend next_next_ft_us_herokuapp_com {
	.connect_timeout = 1s;
	.dynamic = true;
	.port = "80";
	.host = "next-next-ft-us.herokuapp.com";
	.first_byte_timeout = 15s;
	.max_connections = 200;
	.between_bytes_timeout = 10s;
	.share_key = "6TquV5hGGuFYfIDQumwitW";

	.probe = {
		.request = "HEAD /__gtg HTTP/1.1"  "Host: next-next-ft-us.herokuapp.com" "Connection: close" "User-Agent: Varnish/fastly (healthcheck)";
		.window = 5;
		.threshold = 1;
		.timeout = 2s;
		.initial = 5;
		.expected_response = 200;
		.interval = 30s;
	  }
}

backend even_faster_ft {
	.connect_timeout = 1s;
	.dynamic = true;
	.port = "80";
	.host = "next-next-ft-s3.s3-website-eu-west-1.amazonaws.com";
	.first_byte_timeout = 15s;
	.max_connections = 200;
	.between_bytes_timeout = 10s;
	.share_key = "6TquV5hGGuFYfIDQumwitW";

	.probe = {
		.request = "HEAD /evenfasterft HTTP/1.1"  "Host: next-next-ft-s3.s3-website-eu-west-1.amazonaws.com" "Connection: close" "User-Agent: Varnish/fastly (healthcheck)";
		.window = 5;
		.threshold = 1;
		.timeout = 2s;
		.initial = 5;
		.expected_response = 200;
		.interval = 30s;
	  }
}

sub vcl_recv {
#FASTLY recv
	# Force SSL
	if (!req.http.Fastly-SSL) {
		error 801 "Force TLS";
	}

	if (req.url ~ "^\/evenfasterft") {
		set req.backend = even_faster_ft;
		set req.http.Host = "next-next-ft-s3.s3-website-eu-west-1.amazonaws.com";
	} else {
		set req.backend = next_next_ft_us_herokuapp_com;
		set req.http.Host = "next-next-ft-us.herokuapp.com";
	}

	if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
		return(pass);
	}

	return(lookup);
}

sub vcl_fetch {
#FASTLY fetch

  if ((beresp.status == 500 || beresp.status == 503) && req.restarts < 1 && (req.request == "GET" || req.request == "HEAD")) {
	restart;
  }

  if(req.restarts > 0 ) {
	set beresp.http.Fastly-Restarts = req.restarts;
  }

  if (beresp.http.Set-Cookie) {
	set req.http.Fastly-Cachetype = "SETCOOKIE";
	return (pass);
  }

  if (beresp.http.Cache-Control ~ "private") {
	set req.http.Fastly-Cachetype = "PRIVATE";
	return (pass);
  }

  if (beresp.status == 500 || beresp.status == 503) {
	set req.http.Fastly-Cachetype = "ERROR";
	set beresp.ttl = 1s;
	set beresp.grace = 5s;
	return (deliver);
  }

  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
	# keep the ttl here
  } else {
	# apply the default ttl
	set beresp.ttl = 3600s;
  }

  return(deliver);
}

sub vcl_hit {
#FASTLY hit

  if (!obj.cacheable) {
	return(pass);
  }
  return(deliver);
}

sub vcl_miss {
#FASTLY miss
  return(fetch);
}

sub vcl_deliver {
#FASTLY deliver
  return(deliver);
}

sub vcl_error {
#FASTLY error
	if (obj.status == 801) {
		set obj.status = 301;
		set obj.response = "Moved Permanently";
		set obj.http.Location = "https://" req.http.host req.url;
		synthetic {""};
		return (deliver);
	}
}

sub vcl_pass {
#FASTLY pass
}
