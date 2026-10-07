// Node Stats API — exposes /api/nodes with CPU% and RAM for all nodes in the k3s cluster.
// Reads metrics from the metrics-server API (metrics.k8s.io/v1beta1).
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

// NodeStat represents the statistics of a node.
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

// Response is the structure of the JSON response.
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
		log.Fatalf("Error configuring Kubernetes: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Error creating Kubernetes client: %v", err)
	}

	// Client for metrics-server — optional; if the API is not enabled, continue without metrics
	var metricsCS *metricsclientset.Clientset
	metricsCS, err = metricsclientset.NewForConfig(config)
	if err != nil {
		log.Printf("metrics-server API unavailable (%v): metrics will be reported as '-'", err)
		metricsCS = nil
	}

	mux := http.NewServeMux()

	// GET /api/nodes → full list with CPU/RAM
	mux.HandleFunc("/api/nodes", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		nodeList, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{})
		if err != nil {
			http.Error(w, fmt.Sprintf("Error listing nodes: %v", err), http.StatusBadGateway)
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

	// GET /api/nodes/k8s-cp1 → single node
	mux.HandleFunc("/api/nodes/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		nodeName := strings.TrimPrefix(r.URL.Path, "/api/nodes/")
		if nodeName == "" || strings.Contains(nodeName, "/") {
			http.Error(w, "Node name required: /api/nodes/<name>", http.StatusBadRequest)
			return
		}

		node, err := clientset.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
		if err != nil {
			http.Error(w, fmt.Sprintf("Node not found: %v", err), http.StatusNotFound)
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

	// GET / — API info
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{
  "service": "node-stats-api",
  "version": "1.0.0",
  "description": "CPU and RAM for all nodes in the k3s cluster",
  "endpoints": {
    "/api/nodes": "List all nodes with CPU% and RAM",
    "/api/nodes/{name}": "Single node detail",
    "/health": "Health check"
  }
}`))
	})

	log.Printf("Node Stats API listening on :%s", port)
	log.Printf("   GET http://localhost:%s/api/nodes      → all nodes (CPU + RAM)", port)
	log.Printf("   GET http://localhost:%s/api/nodes/{id} → single node", port)
	log.Printf("   GET http://localhost:%s/health         → health check", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}

// buildNodeStats processes all nodes and returns the statistics and totals.
func buildNodeStats(clientset *kubernetes.Clientset, metricsCS *metricsclientset.Clientset, nodeList *v1.NodeList) ([]NodeStat, float64, float64) {
	var stats []NodeStat
	var cpuPct, memPct float64

	for _, node := range nodeList.Items {
		// Determine the role
		role := "worker"
		if _, hasRole := node.Labels["node-role.kubernetes.io/control-plane"]; hasRole {
			role = "control-plane"
		} else if _, hasEtcd := node.Labels["node-role.kubernetes.io/etcd"]; hasEtcd {
			role = "etcd"
		}

		// Status
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

		// Kernel and OS
		kernel := node.Status.NodeInfo.KernelVersion
		os := node.Status.NodeInfo.OSImage

		// Uptime from the timestamp of the last allocated resource
		uptime := "-"
		if !node.Status.AllocationMeta.AdditionalLabels.IsZero() {
			// Not directly accessible, we compute it from the lastTransitionTime
		}
		// Look in the Ready condition
		for _, cond := range node.Status.Conditions {
			if cond.Type == v1.NodeReady {
				uptime = cond.LastHeartbeatTime.Format("2006-01-02 15:04:05")
				break
			}
		}

		// CPU and RAM metrics (from the metrics-server, if available)
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

				// Compute the percentages
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

// buildSingleNodeStats processes a single node.
func buildSingleNodeStats(clientset *kubernetes.Clientset, metricsCS *metricsclientset.Clientset, node *v1.Node) []NodeStat {
	nodeList := &v1.NodeList{Items: []v1.Node{*node}}
	stats, _, _ := buildNodeStats(clientset, metricsCS, nodeList)
	return stats
}

// loadKubeConfig loads the Kubernetes configuration from file or environment.
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

// round rounds a float to n decimals.
func round(val float64, precision int) float64 {
	multiplier := math.Pow(10, float64(precision))
	return math.Round(val*multiplier) / multiplier
}

// formatQuantity formats a ResourceQuantity as a readable string.
func formatQuantity(q string) string {
	return q
}
