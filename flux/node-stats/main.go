// Node Stats API — espone /api/nodes con CPU% e memoria RAM di tutti i nodi del cluster k3s.
// Legge le metriche dalle metrics-server API (metrics.k8s.io/v1beta1).
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strings"
	"time"

	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/metrics/pkg/apis/metrics/v1beta1"
	metricsclientset "k8s.io/metrics/pkg/client/clientset_generated/clientset"
)

// NodeStat rappresenta le statistiche di un nodo.
type NodeStat struct {
	Name     string  `json:"name"`
	Status   string  `json:"status"`
	Role     string  `json:"role"`
	CPUUsed  string  `json:"cpuUsed"`
	CPUPct   float64 `json:"cpuPercent"`
	MemUsed  string  `json:"memUsed"`
	MemPct   float64 `json:"memPercent"`
	MemTotal string  `json:"memTotal"`
	Uptime   string  `json:"uptime"`
	Kernel   string  `json:"kernel"`
	OS       string  `json:"os"`
}

// Response è la struttura della risposta JSON.
type Response struct {
	Cluster  string      `json:"cluster"`
	Nodes    []NodeStat  `json:"nodes"`
	TotalCPU float64     `json:"totalCPUPercent"`
	TotalMem float64     `json:"totalMemPercent"`
	Count    int         `json:"nodeCount"`
	At       string      `json:"at"`
	Source   string      `json:"source"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	config, err := loadKubeConfig()
	if err != nil {
		log.Fatalf("Errore configurazione Kubernetes: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Errore creazione client Kubernetes: %v", err)
	}

	// Client per metrics-server — opzionale, se l'API non è abilitata continua senza metriche
	var metricsCS *metricsclientset.Clientset
	metricsCS, err = metricsclientset.NewForConfig(config)
	if err != nil {
		log.Printf("⚠️ metrics-server API non disponibile (%v): le metriche saranno riportate come '-'", err)
		metricsCS = nil
	}

	mux := http.NewServeMux()

	// GET /api/nodes → lista completa con CPU/RAM
	mux.HandleFunc("/api/nodes", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Metodo non consentito", http.StatusMethodNotAllowed)
			return
		}

		nodeList, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{})
		if err != nil {
			http.Error(w, fmt.Sprintf("Errore lista nodi: %v", err), http.StatusBadGateway)
			return
		}

		stats, cpuPct, memPct := buildNodeStats(clientset, metricsCS, nodeList)
		totalNodes := len(stats)
		if totalNodes == 0 {
			totalNodes = 1
		}

		resp := Response{
			Cluster:  "k3s-homelab",
			Nodes:    stats,
			TotalCPU: round(cpuPct/float64(totalNodes), 2),
			TotalMem: round(memPct/float64(totalNodes), 2),
			Count:    len(nodeList.Items),
			At:       time.Now().UTC().Format(time.RFC3339),
			Source:   "metrics-server",
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	// GET /api/nodes/k8s-cp1 → singolo nodo
	mux.HandleFunc("/api/nodes/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Metodo non consentito", http.StatusMethodNotAllowed)
			return
		}

		nodeName := strings.TrimPrefix(r.URL.Path, "/api/nodes/")
		if nodeName == "" || strings.Contains(nodeName, "/") {
			http.Error(w, "Nome nodo richiesto: /api/nodes/<nome>", http.StatusBadRequest)
			return
		}

		node, err := clientset.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
		if err != nil {
			http.Error(w, fmt.Sprintf("Nodo non trovato: %v", err), http.StatusNotFound)
			return
		}

		stats := buildSingleNodeStats(clientset, metricsCS, node)
		resp := Response{
			Cluster: "k3s-homelab",
			Nodes:   stats,
			Count:   1,
			At:      time.Now().UTC().Format(time.RFC3339),
			Source:  "metrics-server",
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	// GET /health
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","service":"node-stats","version":"1.0.0","timestamp":"` + time.Now().UTC().Format(time.RFC3339) + `"}`))
	})

	// GET / — info API
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{
  "service": "node-stats-api",
  "version": "1.0.0",
  "description": "CPU e memoria RAM di tutti i nodi del cluster k3s",
  "endpoints": {
    "/api/nodes": "Lista tutti i nodi con CPU% e RAM",
    "/api/nodes/{name}": "Dettaglio singolo nodo",
    "/health": "Health check"
  }
}`))
	})

	log.Printf("🚀 Node Stats API in ascolto su :%s", port)
	log.Printf("   GET http://localhost:%s/api/nodes      → tutti i nodi (CPU + RAM)", port)
	log.Printf("   GET http://localhost:%s/api/nodes/{id} → singolo nodo", port)
	log.Printf("   GET http://localhost:%s/health         → health check", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Errore server: %v", err)
	}
}

// buildNodeStats elabora tutti i nodi e restituisce le statistiche e i totali.
func buildNodeStats(clientset *kubernetes.Clientset, metricsCS *metricsclientset.Clientset, nodeList *v1.NodeList) ([]NodeStat, float64, float64) {
	var stats []NodeStat
	var cpuPct, memPct float64

	for _, node := range nodeList.Items {
		// Determina il ruolo
		role := "worker"
		if _, hasRole := node.Labels["node-role.kubernetes.io/control-plane"]; hasRole {
			role = "control-plane"
		} else if _, hasEtcd := node.Labels["node-role.kubernetes.io/etcd"]; hasEtcd {
			role = "etcd"
		}

		// Stato
		status := "Unknown"
		for _, cond := range node.Status.Conditions {
			if cond.Type == v1.NodeReady {
				if cond.Status == v1.ConditionTrue {
					status = "Ready"
				} else {
					status = "NotReady"
				}
				break
			}
		}

		// Kernel e OS
		kernel := node.Status.NodeInfo.KernelVersion
		os := node.Status.NodeInfo.OSImage

		// Uptime dal timestamp dell'ultima risorsa allocata
		uptime := "-"
		if !node.Status.AllocationMeta.AdditionalLabels.IsZero() {
			// Non direttamente accessibile, calcoliamo dal lastTransitionTime
		}
		// Cerciamo nel Ready condition
		for _, cond := range node.Status.Conditions {
			if cond.Type == v1.NodeReady {
				uptime = cond.LastHeartbeatTime.Format("2006-01-02 15:04:05")
				break
			}
		}

		// Metriche CPU e RAM (dal metrics-server, se disponibile)
		cpuStr := "-"
		cpuPctVal := 0.0
		memStr := "-"
		memTotalStr := "-"
		memPctVal := 0.0

		if metricsCS != nil {
			nodeMetric, err := metricsCS.TopologyV1beta1().NodeMetricses().Get(context.TODO(), node.Name, metav1.GetOptions{})
			if err == nil {
				cpuStr = nodeMetric.Usage.Cpu().String()
				memStr = nodeMetric.Usage.Memory().String()
				memTotalStr = formatQuantity(node.Status.Allocatable.Cpu())

				// Calcola le percentuali
				cpuAlloc := node.Status.Allocatable.Cpu().MilliValue()
				cpuUsed := nodeMetric.Usage.Cpu().MilliValue()
				memAlloc := node.Status.Allocatable.Memory().Value()
				memUsed := nodeMetric.Usage.Memory().Value()

				if cpuAlloc > 0 {
					cpuPctVal = round((float64(cpuUsed)/float64(cpuAlloc))*100, 2)
				}
				if memAlloc > 0 {
					memPctVal = round((float64(memUsed)/float64(memAlloc))*100, 2)
					memTotalStr = node.Status.Allocatable.Memory().String()
				}
			}
		}

		stat := NodeStat{
			Name:     node.Name,
			Status:   status,
			Role:     role,
			CPUUsed:  cpuStr,
			CPUPct:   cpuPctVal,
			MemUsed:  memStr,
			MemPct:   memPctVal,
			MemTotal: memTotalStr,
			Uptime:   uptime,
			Kernel:   kernel,
			OS:       os,
		}

		stats = append(stats, stat)
		cpuPct += cpuPctVal
		memPct += memPctVal
	}

	return stats, cpuPct, memPct
}

// buildSingleNodeStats elabora un singolo nodo.
func buildSingleNodeStats(clientset *kubernetes.Clientset, metricsCS *metricsclientset.Clientset, node *v1.Node) []NodeStat {
	nodeList := &v1.NodeList{Items: []v1.Node{*node}}
	stats, _, _ := buildNodeStats(clientset, metricsCS, nodeList)
	return stats
}

// loadKubeConfig carica la configurazione Kubernetes da file o ambiente.
func loadKubeConfig() (*rest.Config, error) {
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		home, _ := os.UserHomeDir()
		kubeconfig = home + "/.kube/config"
		if _, err := os.Stat(kubeconfig); err != nil {
			kubeconfig = "/var/run/secrets/kubernetes.io/serviceaccount/config"
		}
	}
	return clientcmd.BuildConfigFromFlags("", kubeconfig)
}

// round arrotonda un float a n decimali.
func round(val float64, precision int) float64 {
	multiplier := math.Pow(10, float64(precision))
	return math.Round(val*multiplier) / multiplier
}

// formatQuantity formatta una ResourceQuantity in stringa leggibile.
func formatQuantity(q string) string {
	return q
}
