<?xml version="1.0" encoding="UTF-8"?>
<Context>

  <!-- Watch web.xml changes -->
  <WatchedResource>WEB-INF/web.xml</WatchedResource>
  <WatchedResource>${catalina.base}/conf/web.xml</WatchedResource>

  <!--
    JNDI Resource (Optional)

    - 기본 ICR 솔루션 구성에서는 사용하지 않음
    - DB 연결은 Spring Boot external yml(icr-datasource.yml)로 처리
    - 고객사 정책상 JNDI가 필요할 경우, 아래 Resource를 참고하여
      수동으로 context.xml을 수정하면 됨
  -->
  <!--
  <Resource
      name="jdbc/icrDataSource"
      auth="Container"
      type="javax.sql.DataSource"
      maxTotal="50"
      maxIdle="10"
      maxWaitMillis="5000"
      driverClassName="oracle.jdbc.OracleDriver"
      url="jdbc:oracle:thin:@//HOST:PORT/SERVICE"
      username="USER"
      password="PWD"
  />
  -->

</Context>

