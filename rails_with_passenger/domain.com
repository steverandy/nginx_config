server {
  listen 80;
  server_name www.domain.com;
  rewrite ^/(.*) http://domain.com/$1 permanent;
}

server {
  listen 80;
  server_name domain.com subdomain.domain.com;
  access_log logs/domain.com.access.log main;
  root /path/to/public;
  passenger_enabled on;
  client_max_body_size 30m;
  add_header "X-UA-Compatible" "IE=edge,chrome=1";

  location ~* \.(js|css|jpg|jpeg|gif|png)$ {
    if (!-f $request_filename) {
      break;
      passenger_enabled on;
    }
    if ($query_string ~* "^[0-9]{10}$") {
      expires max;
      break;
    }
  }

  if (-f $document_root/system/maintenance.html) {
    return 503;
  }

  error_page 404 /404.html;
  error_page 500 502 504 /500.html;
  error_page 503 @503;

  location @503 {
    error_page 405 = /system/maintenance.html;
    if (-f $request_filename) {
      break;
    }
    rewrite ^(.*)$ /system/maintenance.html break;
  }
}
