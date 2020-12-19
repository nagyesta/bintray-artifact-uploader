FROM nagyesta-docker-releases.bintray.io/alpine-curl-git:1.0.0
LABEL maintainer="nagyesta@gmail.com"
ADD entrypoint.sh /entrypoint.sh
CMD [ "sh", "-c", "echo $HOME" ]
ENTRYPOINT ["sh", "/entrypoint.sh"] 
