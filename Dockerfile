FROM nginx:alpine
ARG FAULTY=false
COPY index.html /usr/share/nginx/html/index.html
RUN if [ "$FAULTY" = "true" ]; then echo "deliberate_fault on;" >> /etc/nginx/nginx.conf; fi
EXPOSE 80