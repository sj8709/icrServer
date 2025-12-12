<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee
                             https://jakarta.ee/xml/ns/jakartaee/web-app_5_0.xsd"
         version="5.0">

    <display-name>ICR Solution Default Web Configuration</display-name>

    <!-- ============================================================= -->
    <!-- Global UTF-8 Encoding (Servlet 4.0+ 표준)                      -->
    <!-- ============================================================= -->
    <request-character-encoding>UTF-8</request-character-encoding>
    <response-character-encoding>UTF-8</response-character-encoding>

    <!-- ============================================================= -->
    <!-- UTF-8 Filter (Tomcat + Spring 환경에서 가장 안전한 인코딩 보정) -->
    <!-- ============================================================= -->
    <filter>
        <filter-name>encodingFilter</filter-name>
        <filter-class>org.apache.catalina.filters.SetCharacterEncodingFilter</filter-class>
        <init-param>
            <param-name>encoding</param-name>
            <param-value>UTF-8</param-value>
        </init-param>
        <init-param>
            <param-name>ignore</param-name>
            <param-value>false</param-value>
        </init-param>
    </filter>

    <filter-mapping>
        <filter-name>encodingFilter</filter-name>
        <url-pattern>/*</url-pattern>
    </filter-mapping>

    <!-- ============================================================= -->
    <!-- Default Servlet (정적 파일 처리)                               -->
    <!-- ============================================================= -->
    <servlet>
        <servlet-name>default</servlet-name>
        <servlet-class>org.apache.catalina.servlets.DefaultServlet</servlet-class>
        <init-param>
            <param-name>debug</param-name>
            <param-value>0</param-value>
        </init-param>
        <init-param>
            <param-name>listings</param-name>
            <param-value>false</param-value>
        </init-param>
        <load-on-startup>1</load-on-startup>
    </servlet>

    <servlet-mapping>
        <servlet-name>default</servlet-name>
        <url-pattern>/</url-pattern>
    </servlet-mapping>

    <!-- ============================================================= -->
    <!-- JSP Servlet 설정 (Tomcat 10/11 Jakarta JSP)                    -->
    <!-- ============================================================= -->
    <servlet>
        <servlet-name>jsp</servlet-name>
        <servlet-class>org.apache.jasper.servlet.JspServlet</servlet-class>

        <init-param>
            <param-name>fork</param-name>
            <param-value>false</param-value>
        </init-param>

        <!-- 보안: X-Powered-By 헤더 숨김 -->
        <init-param>
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

    <!-- ============================================================= -->
    <!-- 기본 Welcome 파일 목록                                         -->
    <!-- ============================================================= -->
    <welcome-file-list>
        <welcome-file>index.html</welcome-file>
        <welcome-file>index.htm</welcome-file>
        <welcome-file>index.jsp</welcome-file>
    </welcome-file-list>

    <!-- ============================================================= -->
    <!-- Error Page Mapping                                             -->
    <!-- Spring Boot 정적 리소스 구조 기준                              -->
    <!-- /WEB-INF/classes/static/html/error/XXX.html                   -->
    <!-- ============================================================= -->

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

