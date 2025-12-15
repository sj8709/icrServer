<?xml version="1.0" encoding="UTF-8"?>
<!--
    context.xml - Tomcat 컨텍스트 설정

    생성: install-core.sh에 의해 템플릿에서 복사
    위치: $INSTALL_BASE/config/tomcat/context.xml -> $TOMCAT_HOME/conf/context.xml (심볼릭 링크)

    이 파일은 모든 웹 애플리케이션에 공통 적용되는 컨텍스트 설정입니다.
    애플리케이션별 설정은 WAR 내부 META-INF/context.xml에서 오버라이드됩니다.
-->
<Context>

    <!-- ===================================================================== -->
    <!--  0. 웹 리소스 캐시 설정                                                -->
    <!-- ===================================================================== -->
    <!--
        Spring Boot 애플리케이션은 WEB-INF/classes 아래 리소스 파일이 많아
        기본 캐시 크기(10MB)가 부족할 수 있음.
        cacheMaxSize: KB 단위 (102400 = 100MB)
    -->
    <Resources cachingAllowed="true" cacheMaxSize="102400" />

    <!-- ===================================================================== -->
    <!--  1. 파일 변경 감시                                                     -->
    <!-- ===================================================================== -->

    <!-- 아래 파일 변경 시 컨텍스트 자동 리로드 -->
    <WatchedResource>WEB-INF/web.xml</WatchedResource>
    <WatchedResource>${catalina.base}/conf/web.xml</WatchedResource>

    <!-- ===================================================================== -->
    <!--  2. JNDI 데이터소스 (선택사항)                                         -->
    <!-- ===================================================================== -->
    <!--
        기본 구성:
          - ICR 솔루션은 JNDI를 사용하지 않음
          - DB 연결은 Spring Boot 외부 설정 (icr-datasource.yml)으로 처리

        JNDI가 필요한 경우:
          - 고객사 정책상 JNDI 필수인 경우 아래 예시 참고
          - $INSTALL_BASE/config/tomcat/context.xml 직접 수정
          - ICR_FORCE_REGEN=Y 재설치 시 덮어쓰기 주의
    -->

    <!-- Oracle 예시 -->
    <!--
    <Resource
        name="jdbc/icrDataSource"
        auth="Container"
        type="javax.sql.DataSource"
        factory="org.apache.tomcat.jdbc.pool.DataSourceFactory"
        maxActive="50"
        maxIdle="10"
        maxWait="5000"
        driverClassName="oracle.jdbc.OracleDriver"
        url="jdbc:oracle:thin:@//HOST:PORT/SERVICE"
        username="USER"
        password="PWD"
        validationQuery="SELECT 1 FROM DUAL"
        testOnBorrow="true" />
    -->

    <!-- PostgreSQL 예시 -->
    <!--
    <Resource
        name="jdbc/icrDataSource"
        auth="Container"
        type="javax.sql.DataSource"
        factory="org.apache.tomcat.jdbc.pool.DataSourceFactory"
        maxActive="50"
        maxIdle="10"
        maxWait="5000"
        driverClassName="org.postgresql.Driver"
        url="jdbc:postgresql://HOST:PORT/DATABASE"
        username="USER"
        password="PWD"
        validationQuery="SELECT 1"
        testOnBorrow="true" />
    -->

    <!-- MySQL 예시 -->
    <!--
    <Resource
        name="jdbc/icrDataSource"
        auth="Container"
        type="javax.sql.DataSource"
        factory="org.apache.tomcat.jdbc.pool.DataSourceFactory"
        maxActive="50"
        maxIdle="10"
        maxWait="5000"
        driverClassName="com.mysql.cj.jdbc.Driver"
        url="jdbc:mysql://HOST:PORT/DATABASE?useSSL=false&amp;serverTimezone=Asia/Seoul"
        username="USER"
        password="PWD"
        validationQuery="SELECT 1"
        testOnBorrow="true" />
    -->

</Context>
