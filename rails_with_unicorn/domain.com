# Upstream name must be unique.
upstream application_app_server {
  server unix:/path/to/unicorn.sock fail_timeout=0;
}

server {
  listen 80;
  server_name www.domain.com;
  rewrite ^/(.*) http://domain.com/$1 permanent;
}

server {
  listen 80;
  server_name domain.com subdomain.domain.com;
  access_log logs/domain.com.access.log main;
  client_max_body_size 30m;
  add_header X-UA-Compatible "IE=edge,chrome=1";
  root /path/to/public;

  try_files $uri/index.html $uri.html $uri @app;

  # Used only for serving files from MongoDB GridFS.
  # location ^~ /gridfs/ {
  #   proxy_ignore_headers Set-Cookie;
  #   proxy_hide_header Set-Cookie;
  #   proxy_cache all;
  #   proxy_pass http://application_app_server;
  # }

  # Used only for serving static files.
  location ~* \.(js|css|jpg|jpeg|gif|png)$ {
    if (!-f $request_filename) {
      proxy_pass http://application_app_server;
      break;
    }
    if ($query_string ~* "^[0-9]+$") {
      expires max;
      break;
    }
  }

  # Used to pass the request to unicorn.
  location @app {
    # proxy_set_header X-Forwarded-Proto https; # Enable this if and only if you use HTTPS.
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_redirect off;
    proxy_ignore_headers Set-Cookie;
    proxy_cache all;
    proxy_pass http://application_app_server;
  }

  # Used for serving maintenance page.
  location @503 {
    error_page 405 = /system/maintenance.html;
    if (-f $request_filename) {
      break;
    }
    rewrite ^(.*)$ /system/maintenance.html break;
  }

  # Show maintenance page if the file exists.
  if (-f $document_root/system/maintenance.html) {
    return 503;
  }

  error_page 404 /404.html;
  error_page 500 502 504 /500.html;
  error_page 503 @503;
}
