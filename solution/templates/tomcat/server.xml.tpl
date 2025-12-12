<?xml version="1.0" encoding="UTF-8"?>
<!--
    server.xml - Tomcat 서버 설정

    생성: install-core.sh에 의해 템플릿에서 자동 생성
    위치: $INSTALL_BASE/config/tomcat/server.xml -> $TOMCAT_HOME/conf/server.xml (심볼릭 링크)

    토큰 목록 (site.conf 값으로 치환):
      @WAS_SHUTDOWN_PORT@          Tomcat 종료 포트
      @WAS_HTTP_PORT@              HTTP 커넥터 포트
      @WAS_HTTPS_PORT@             HTTPS 커넥터 포트
      @WAS_APP_BASE@               애플리케이션 배포 디렉토리
      @WAS_SSL_KEYSTORE_FILE@      SSL 인증서 파일명
      @WAS_SSL_KEYSTORE_PASSWORD@  SSL 인증서 비밀번호

    조건부 토큰:
      @HTTPS_CONNECTOR_BEGIN@ / @HTTPS_CONNECTOR_END@
        - WAS_ENABLE_HTTPS=Y: HTTPS 커넥터 활성화 (주석 제거)
        - WAS_ENABLE_HTTPS=N: HTTPS 커넥터 비활성화 (주석 처리)
-->

<Server port="@WAS_SHUTDOWN_PORT@" shutdown="SHUTDOWN">

    <!-- ===================================================================== -->
    <!--  1. 리스너 설정                                                        -->
    <!-- ===================================================================== -->

    <!-- 버전 정보 로깅 -->
    <Listener className="org.apache.catalina.startup.VersionLoggerListener" />

    <!-- 보안 리스너 -->
    <Listener className="org.apache.catalina.security.SecurityListener" />

    <!-- APR/Native 라이브러리 (SSL 하드웨어 가속) -->
    <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />

    <!-- JRE 메모리 누수 방지 -->
    <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />

    <!-- 글로벌 리소스 라이프사이클 -->
    <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />

    <!-- ThreadLocal 누수 방지 -->
    <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

    <!-- ===================================================================== -->
    <!--  2. 글로벌 JNDI 리소스                                                 -->
    <!-- ===================================================================== -->

    <GlobalNamingResources>
        <!-- 사용자 데이터베이스 (tomcat-users.xml) -->
        <Resource name="UserDatabase" auth="Container"
                  type="org.apache.catalina.UserDatabase"
                  description="User database that can be updated and saved"
                  factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
                  pathname="conf/tomcat-users.xml" />
    </GlobalNamingResources>

    <!-- ===================================================================== -->
    <!--  3. Service: Catalina                                                 -->
    <!-- ===================================================================== -->

    <Service name="Catalina">

        <!-- ================================================================= -->
        <!--  3-1. HTTP 커넥터                                                 -->
        <!-- ================================================================= -->

        <Connector
                port="@WAS_HTTP_PORT@"
                protocol="HTTP/1.1"
                connectionTimeout="20000"
                redirectPort="@WAS_HTTPS_PORT@"
                maxParameterCount="10000"
                URIEncoding="UTF-8"
                server="Secure Server" />

        <!-- ================================================================= -->
        <!--  3-2. HTTPS 커넥터 (WAS_ENABLE_HTTPS 플래그로 활성화/비활성화)     -->
        <!-- ================================================================= -->

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
                <Certificate
                        certificateKeystoreFile="conf/@WAS_SSL_KEYSTORE_FILE@"
                        certificateKeystorePassword="@WAS_SSL_KEYSTORE_PASSWORD@"
                        type="RSA" />
            </SSLHostConfig>
        </Connector>
        <!-- @HTTPS_CONNECTOR_END@ -->

        <!-- ================================================================= -->
        <!--  3-3. AJP 커넥터 (기본 비활성화)                                   -->
        <!--       Apache HTTP Server 연동 시 주석 해제                        -->
        <!--       반드시 secretRequired + 방화벽 설정 필요                    -->
        <!-- ================================================================= -->
        <!--
        <Connector
                protocol="AJP/1.3"
                port="8009"
                redirectPort="@WAS_HTTPS_PORT@"
                secretRequired="true"
                secret="YOUR_AJP_SECRET"
                address="127.0.0.1" />
        -->

        <!-- ================================================================= -->
        <!--  3-4. Engine                                                      -->
        <!-- ================================================================= -->

        <Engine name="Catalina" defaultHost="localhost">

            <!-- LockOutRealm: 무차별 대입 공격 방지 -->
            <Realm className="org.apache.catalina.realm.LockOutRealm">
                <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
                       resourceName="UserDatabase" />
            </Realm>

            <!-- ============================================================= -->
            <!--  3-5. Host                                                    -->
            <!-- ============================================================= -->

            <Host name="localhost"
                  appBase="@WAS_APP_BASE@"
                  unpackWARs="true"
                  autoDeploy="false">

                <!-- 액세스 로그 -->
                <Valve className="org.apache.catalina.valves.AccessLogValve"
                       directory="logs"
                       prefix="localhost_access_log"
                       suffix=".txt"
                       pattern="%h %l %u %t &quot;%r&quot; %s %b" />

                <!-- 리버스 프록시 지원 (L4/L7/Nginx 뒤에서 실제 클라이언트 IP 식별) -->
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
