<?xml version="1.0" encoding="UTF-8"?>
<!--
    Tomcat server.xml 템플릿

    - @WAS_HTTP_PORT@   : site.conf 의 WAS_HTTP_PORT 값으로 치환
    - @WAS_HTTPS_PORT@  : site.conf 의 WAS_HTTPS_PORT 값으로 치환
    - @WAS_APP_BASE@    : site.conf 의 WAS_APP_BASE 값으로 치환
    - @HTTPS_CONNECTOR_BEGIN@ / @HTTPS_CONNECTOR_END@
        * install.sh 에서 WAS_ENABLE_HTTPS 플래그에 따라
          HTTPS 커넥터를 살리거나(주석 제거) 통째로 주석 한 줄로 교체
-->

<Server port="8005" shutdown="SHUTDOWN">

    <!-- 기본 리스너들 (Tomcat 표준 + 메모리릭 방지 등) -->
    <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
    <Listener className="org.apache.catalina.security.SecurityListener" />
    <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
    <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
    <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
    <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

    <!-- Global JNDI resources -->
    <GlobalNamingResources>
        <Resource name="UserDatabase" auth="Container"
                  type="org.apache.catalina.UserDatabase"
                  description="User database that can be updated and saved"
                  factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
                  pathname="conf/tomcat-users.xml" />
    </GlobalNamingResources>

    <!-- =================================================================== -->
    <!-- Service: Catalina                                                   -->
    <!-- =================================================================== -->
    <Service name="Catalina">

        <!-- HTTP/1.1 기본 커넥터 -->
        <Connector
                port="@WAS_HTTP_PORT@"
                protocol="HTTP/1.1"
                connectionTimeout="20000"
                redirectPort="@WAS_HTTPS_PORT@"
                maxParameterCount="10000"
                URIEncoding="UTF-8"
                server="Secure Server" />

        <!-- =================================================================== -->
        <!-- HTTPS 커넥터 (플래그로 on/off)                                       -->
        <!-- =================================================================== -->

        <!-- @HTTPS_CONNECTOR_BEGIN@ -->
        <Connector
                port="@WAS_HTTPS_PORT@"
                protocol="org.apache.coyote.http11.Http11NioProtocol"
                maxThreads="150"
                SSLEnabled="true"
                scheme="https"
                secure="true"
                clientAuth="false"
                sslProtocol="TLS">

            <SSLHostConfig>
                <!--
                    keystore 설정은 샘플 값입니다 (추측입니다).
                    실제 운영에서는 keystore 경로/비밀번호/alias 를 반드시 교체해야 합니다.
                -->
                <Certificate
                        certificateKeystoreFile="conf/localhost-rsa.jks"
                        certificateKeystorePassword="changeit"
                        type="RSA" />
            </SSLHostConfig>
        </Connector>
        <!-- @HTTPS_CONNECTOR_END@ -->

        <!-- AJP 는 기본 비활성. 필요하면 방화벽/secret 설정 후 주석 해제 -->
        <!--
        <Connector
                protocol="AJP/1.3"
                port="8009"
                redirectPort="@WAS_HTTPS_PORT@"
                secretRequired="true"
                address="::1" />
        -->

        <!-- =================================================================== -->
        <!-- Engine + Host                                                      -->
        <!-- =================================================================== -->

        <Engine name="Catalina" defaultHost="localhost">

            <!-- LockOutRealm + UserDatabaseRealm -->
            <Realm className="org.apache.catalina.realm.LockOutRealm">
                <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
                       resourceName="UserDatabase" />
            </Realm>

            <!-- Host 설정 -->
            <Host name="localhost"
                  appBase="@WAS_APP_BASE@"
                  unpackWARs="true"
                  autoDeploy="false">

                <!-- AccessLogValve (필요 시 패턴 조정 가능, 현재는 기본형 / 확실하지 않음) -->
                <Valve className="org.apache.catalina.valves.AccessLogValve"
                       directory="logs"
                       prefix="localhost_access_log"
                       suffix=".txt"
                       pattern="%h %l %u %t &quot;%r&quot; %s %b" />

                <!-- RemoteIpValve: 프록시/L4 뒤에서 클라이언트 IP/HTTPS 판별용 -->
                <Valve className="org.apache.catalina.valves.RemoteIpValve"
                       remoteIpHeader="x-forwarded-for"
                       protocolHeader="x-forwarded-proto"
                       portHeader="x-forwarded-port"
                       requestAttributesEnabled="true"
                       internalProxies=""
                       httpsServerPort="443" />
            </Host>
        </Engine>
    </Service>
</Server>

