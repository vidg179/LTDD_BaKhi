# Runtime-only image: the app is published on the developer machine
# (dotnet publish) because the VPS has about 1 GB of RAM, too little for the SDK.
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY publish/ .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app
ENTRYPOINT ["dotnet", "BaKhi.Api.dll"]
