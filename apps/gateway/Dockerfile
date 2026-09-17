FROM nginx:1.27-alpine

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh \
    && chown -R nginx:nginx /etc/nginx

USER nginx
EXPOSE 8080
ENV BACKEND_HOST=placeholder.invalid
ENTRYPOINT ["/docker-entrypoint.sh"]
