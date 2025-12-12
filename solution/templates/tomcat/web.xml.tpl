<?xml version="1.0" encoding="UTF-8"?>
<!--
    web.xml - Tomcat 기본 웹 설정

    생성: install-core.sh에 의해 템플릿에서 복사
    위치: $INSTALL_BASE/config/tomcat/web.xml -> $TOMCAT_HOME/conf/web.xml (심볼릭 링크)

    이 파일은 Tomcat 전역 웹 설정을 정의합니다.
    애플리케이션별 설정은 WAR 내부 WEB-INF/web.xml에서 오버라이드됩니다.
-->
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee
                             https://jakarta.ee/xml/ns/jakartaee/web-app_5_0.xsd"
         version="5.0">

    <display-name>ICR Solution Default Web Configuration</display-name>

    <!-- ===================================================================== -->
    <!--  1. 전역 UTF-8 인코딩 (Servlet 4.0+ 표준)                              -->
    <!-- ===================================================================== -->

    <request-character-encoding>UTF-8</request-character-encoding>
    <response-character-encoding>UTF-8</response-character-encoding>

    <!-- ===================================================================== -->
    <!--  2. UTF-8 인코딩 필터                                                  -->
    <!--     Tomcat + Spring 환경에서 가장 안전한 인코딩 보정                    -->
    <!-- ===================================================================== -->

    <filter>
        <filter-name>encodingFilter</filter-name>
        <filter-class>org.apache.catalina.filters.SetCharacterEncodingFilter</filter-class>
        <init-param>
            <param-name>encoding</param-name>
            <param-value>UTF-8</param-value>
        </init-param>
        <init-param>
            <!-- ignore=false: 요청에 인코딩이 이미 설정되어 있어도 UTF-8로 강제 -->
            <param-name>ignore</param-name>
            <param-value>false</param-value>
        </init-param>
    </filter>

    <filter-mapping>
        <filter-name>encodingFilter</filter-name>
        <url-pattern>/*</url-pattern>
    </filter-mapping>

    <!-- ===================================================================== -->
    <!--  3. Default Servlet (정적 파일 처리)                                   -->
    <!-- ===================================================================== -->

    <servlet>
        <servlet-name>default</servlet-name>
        <servlet-class>org.apache.catalina.servlets.DefaultServlet</servlet-class>
        <init-param>
            <!-- debug=0: 디버그 로그 비활성화 -->
            <param-name>debug</param-name>
            <param-value>0</param-value>
        </init-param>
        <init-param>
            <!-- listings=false: 디렉토리 목록 노출 방지 (보안) -->
            <param-name>listings</param-name>
            <param-value>false</param-value>
        </init-param>
        <load-on-startup>1</load-on-startup>
    </servlet>

    <servlet-mapping>
        <servlet-name>default</servlet-name>
        <url-pattern>/</url-pattern>
    </servlet-mapping>

    <!-- ===================================================================== -->
    <!--  4. JSP Servlet (Tomcat 10/11 Jakarta JSP)                            -->
    <!-- ===================================================================== -->

    <servlet>
        <servlet-name>jsp</servlet-name>
        <servlet-class>org.apache.jasper.servlet.JspServlet</servlet-class>
        <init-param>
            <!-- fork=false: JSP 컴파일 시 별도 프로세스 생성 안 함 -->
            <param-name>fork</param-name>
            <param-value>false</param-value>
        </init-param>
        <init-param>
            <!-- xpoweredBy=false: X-Powered-By 헤더 숨김 (보안) -->
            <param-name>xpoweredBy</param-name>
            <param-value>false</param-value>
        </init-param>
        <load-on-startup>3</load-on-startup>
    </servlet>

    <servlet-mapping>
        <servlet-name>jsp</servlet-name>
        <url-pattern>*.jsp</url-pattern>
        <url-pattern>*.jspx</url-pattern>
    </servlet-mapping>

    <!-- ===================================================================== -->
    <!--  5. Welcome 파일 목록                                                  -->
    <!-- ===================================================================== -->

    <welcome-file-list>
        <welcome-file>index.html</welcome-file>
        <welcome-file>index.htm</welcome-file>
        <welcome-file>index.jsp</welcome-file>
    </welcome-file-list>

    <!-- ===================================================================== -->
    <!--  6. 에러 페이지 매핑                                                   -->
    <!--     Spring Boot 정적 리소스 구조: /WEB-INF/classes/static/html/error/  -->
    <!-- ===================================================================== -->

    <error-page>
        <error-code>400</error-code>
        <location>/WEB-INF/classes/static/html/error/400.html</location>
    </error-page>

    <error-page>
        <error-code>401</error-code>
        <location>/WEB-INF/classes/static/html/error/401.html</location>
    </error-page>

    <error-page>
        <error-code>402</error-code>
        <location>/WEB-INF/classes/static/html/error/402.html</location>
    </error-page>

    <error-page>
        <error-code>403</error-code>
        <location>/WEB-INF/classes/static/html/error/403.html</location>
    </error-page>

    <error-page>
        <error-code>404</error-code>
        <location>/WEB-INF/classes/static/html/error/404.html</location>
    </error-page>

    <error-page>
        <error-code>500</error-code>
        <location>/WEB-INF/classes/static/html/error/500.html</location>
    </error-page>

</web-app>
