package org.springframework.samples.petclinic.admin;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Configuration pour l'exposition des métriques Prometheus
 * Classe qui permet de personnaliser les métriques exposées par Spring Boot Actuator
 */
@Configuration
public class MonitoringConfig {
    
    private static final Logger logger = LoggerFactory.getLogger(MonitoringConfig.class);
    
    /**
     * Personnalisation du registre de métriques avec des tags communs
     * @param registry Le registre à personnaliser
     * @return Le customizer de registre configuré
     */
    @Bean
    public MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
        logger.info("Configuration des métriques Prometheus avec tags communs");
        return registry -> registry.config()
            .commonTags("application", "admin-server")
            .commonTags("environnement", "minikube");
    }
}
