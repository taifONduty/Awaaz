import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.graphhopper.*;
import com.graphhopper.config.Profile;
import com.graphhopper.jackson.Jackson;
import com.graphhopper.routing.WeightingFactory;
import com.graphhopper.routing.querygraph.VirtualEdgeIteratorState;
import com.graphhopper.routing.weighting.Weighting;
import com.graphhopper.util.*;
import com.graphhopper.util.details.PathDetail;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;

/** Private JSON-lines worker. No HTTP listener, raw-coordinate logs, graph
 * import or shared mutable overlay. One validated snapshot owns each search.
 */
public final class EvidenceRouter {
  private static final ObjectMapper JSON = Jackson.newObjectMapper();
  private static final double ALPHA = 2;
  private static final int MAX_LINE = 4 * 1024 * 1024;
  private static String graphVersion, importDate;
  private static Path cache, artifactDirectory;
  private static Map<String,String> graphFiles;

  record Snapshot(String id, String epoch, String digest, Instant expires, int baseEdges, Map<Integer,Double> values) {
    double index(EdgeIteratorState edge) {
      // Search uses a VirtualEdgeIterator wrapper; path extraction can use the
      // concrete state directly. Detach only virtual IDs to avoid allocating a
      // copy for every ordinary edge visited by A*.
      EdgeIteratorState state=edge.getEdge()>=baseEdges ? edge.detach(false) : edge;
      if (state.getEdge()>=baseEdges && !(state instanceof VirtualEdgeIteratorState))
        throw new IllegalArgumentException("invalid_virtual_edge");
      int key = state instanceof VirtualEdgeIteratorState v ? v.getOriginalEdgeKey() : state.getEdgeKey();
      return values.getOrDefault(key >>> 1, 0.0);
    }
    void checkLease() { if (!expires.isAfter(Instant.now())) throw new IllegalArgumentException("snapshot_expired"); }
  }
  static final class EvidenceWeighting implements Weighting {
    final Weighting base; final Snapshot snapshot;
    EvidenceWeighting(Weighting base, Snapshot snapshot) { this.base=base; this.snapshot=snapshot; }
    // The base admissible lower bound remains valid: penalties are nonnegative.
    public double calcMinWeightPerDistance() { return base.calcMinWeightPerDistance(); }
    public double calcEdgeWeight(EdgeIteratorState edge, boolean reverse) {
      double weight=base.calcEdgeWeight(edge,reverse);
      if (!Double.isFinite(weight)) return weight;
      return weight * (1 + ALPHA * snapshot.index(edge));
    }
    public long calcEdgeMillis(EdgeIteratorState edge, boolean reverse) { return base.calcEdgeMillis(edge,reverse); }
    public double calcTurnWeight(int in, int via, int out) { return base.calcTurnWeight(in,via,out); }
    public long calcTurnMillis(int in, int via, int out) { return base.calcTurnMillis(in,via,out); }
    public boolean hasTurnCosts() { return base.hasTurnCosts(); }
    public String getName() { return base.getName(); }
  }
  static final class Hopper extends GraphHopper implements AutoCloseable {
    protected WeightingFactory createWeightingFactory() {
      WeightingFactory delegate=super.createWeightingFactory();
      return (profile,hints,disableTurns) -> {
        Weighting base=delegate.createWeighting(profile,hints,disableTurns);
        Snapshot snapshot=hints.getObject("awaaz.snapshot",null);
        return snapshot == null ? base : new EvidenceWeighting(base,snapshot);
      };
    }
  }
  static String sha(Path file) throws Exception {
    MessageDigest hash=MessageDigest.getInstance("SHA-256");
    try (InputStream stream=Files.newInputStream(file)) {
      byte[] buffer=new byte[65536]; int read;
      while ((read=stream.read(buffer))>=0) hash.update(buffer,0,read);
    }
    return HexFormat.of().formatHex(hash.digest());
  }
  static Map<String,String> cacheDigests() throws Exception {
    Map<String,String> hashes=new TreeMap<>();
    try (var paths=Files.list(cache)) {
      for (Path file: paths.filter(Files::isRegularFile).sorted().toList()) {
        if (!file.getFileName().toString().matches("[a-z_]+(?:\\.txt)?")) throw new IllegalArgumentException("unexpected_graph_file");
        hashes.put(file.getFileName().toString(),sha(file));
      }
    }
    return Collections.unmodifiableMap(hashes);
  }
  static Instant instant(JsonNode node) {
    if (!node.isTextual() || node.textValue().length()>40) throw new IllegalArgumentException("invalid_snapshot");
    return OffsetDateTime.parse(node.textValue()).toInstant();
  }
  static Snapshot snapshot(JsonNode request, Hopper hopper) throws Exception {
    JsonNode reference=request.get("snapshot");
    if (reference==null || reference.isNull()) return null;
    String id=reference.path("id").asText(), expected=reference.path("sha256").asText();
    if (!id.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") || !expected.matches("[0-9a-f]{64}"))
      throw new IllegalArgumentException("invalid_snapshot");
    Path artifact=artifactDirectory.resolve(id+".jsonl");
    if (Files.isSymbolicLink(artifact) || !Files.isRegularFile(artifact) || Files.size(artifact)>64L*1024*1024 || !expected.equals(sha(artifact)))
      throw new IllegalArgumentException("invalid_snapshot");
    Map<Integer,Double> values=new HashMap<>();
    JsonNode metadata;
    try (BufferedReader reader=Files.newBufferedReader(artifact,StandardCharsets.UTF_8)) {
      String line=boundedLine(reader);
      JsonNode header=JSON.readTree(line);
      metadata=header.path("metadata");
      if (!header.path("format").asText().equals("awaaz-evidence-v1") || !metadata.path("id").asText().equals(id)
        || !metadata.path("graphVersion").asText().equals(graphVersion) || !metadata.path("scoringVersion").asText().equals("reviewed-decay-v1")
        || !metadata.path("safetyCoverage").isNull() || !metadata.path("unknownDefault").path("evidenceIndex").isNull()
        || metadata.path("unknownDefault").path("confidence").asInt(-1)!=0 || metadata.path("unknownDefault").path("uncertainty").asInt(-1)!=1
        || metadata.path("unknownDefault").path("eventClusterCount").asInt(-1)!=0
        || !metadata.path("evidenceEpoch").asText().matches("(?:0|[1-9][0-9]{0,18})")
        || !metadata.path("graphMetadataDigest").asText().matches("[0-9a-f]{64}")) throw new IllegalArgumentException("invalid_snapshot");
      Map<String,String> sourceFiles=new TreeMap<>();
      for (JsonNode file: metadata.path("sourceGraphFiles")) {
        String name=file.path("name").asText(), digest=file.path("sha256").asText();
        if (sourceFiles.put(name,digest)!=null) throw new IllegalArgumentException("invalid_snapshot");
      }
      if (!sourceFiles.equals(graphFiles)) throw new IllegalArgumentException("graph_mismatch");
      Instant created=instant(metadata.path("createdAt")), expires=instant(metadata.path("expiresAt"));
      if (created.isAfter(Instant.now().plusSeconds(5)) || !expires.isAfter(created) || Duration.between(created,expires).toMillis()>120001
        || !expires.isAfter(Instant.now())) throw new IllegalArgumentException("snapshot_expired");
      int previous=-1;
      while ((line=boundedLine(reader))!=null) {
        JsonNode edge=JSON.readTree(line);
        int edgeId=edge.path("edgeId").asInt(-1);
        double value=edge.path("evidenceIndex").asDouble(Double.NaN);
        if (edgeId<=previous || edgeId<0 || edgeId>=hopper.getBaseGraph().getEdges() || !edge.path("edgeId").isIntegralNumber()
          || edge.path("forwardKey").asInt(-1)!=edgeId*2
          || edge.path("reverseKey").asInt(-1)!=edgeId*2+1 || !Double.isFinite(value) || value<=0 || value>0.8
          || !edge.path("evidenceIndex").isNumber() || edge.path("confidence").asDouble(-1)!=0 || edge.path("uncertainty").asDouble(-1)!=1
          || edge.path("eventClusterCount").asInt(-1)<1)
          throw new IllegalArgumentException("invalid_snapshot");
        values.put(edgeId,value); previous=edgeId;
      }
    }
    if (values.size()!=metadata.path("evidencedEdgeCount").asInt(-1)) throw new IllegalArgumentException("invalid_snapshot");
    // Detect mutation between the initial digest and parsing.
    if (!expected.equals(sha(artifact))) throw new IllegalArgumentException("invalid_snapshot");
    return new Snapshot(id,metadata.path("evidenceEpoch").asText(),metadata.path("graphMetadataDigest").asText(),
      instant(metadata.path("expiresAt")),hopper.getBaseGraph().getEdges(),Map.copyOf(values));
  }
  static String boundedLine(Reader reader) throws IOException {
    StringBuilder line=new StringBuilder(); int c;
    while ((c=reader.read())!=-1 && c!='\n') {
      if (line.length()>=MAX_LINE) throw new IOException("line_limit");
      if (c!='\r') line.append((char)c);
    }
    return c==-1 && line.length()==0 ? null : line.toString();
  }
  static double number(JsonNode value, double min, double max) {
    if (!value.isNumber() || !Double.isFinite(value.doubleValue()) || value.doubleValue()<min || value.doubleValue()>max)
      throw new IllegalArgumentException("invalid_request");
    return value.doubleValue();
  }
  static Object route(Hopper hopper, JsonNode input) throws Exception {
    String mode=input.path("mode").asText(), algorithm=input.path("algorithm").asText("astarbi");
    if (!Set.of("car","walk").contains(mode) || !Set.of("astarbi","dijkstrabi").contains(algorithm)) throw new IllegalArgumentException("invalid_request");
    JsonNode origin=input.path("origin"), destination=input.path("destination");
    double aLat=number(origin.path("latitude"),23.62,24.02), aLon=number(origin.path("longitude"),90.2,90.58);
    double bLat=number(destination.path("latitude"),23.62,24.02), bLon=number(destination.path("longitude"),90.2,90.58);
    Snapshot snapshot=snapshot(input,hopper);
    if (snapshot!=null) snapshot.checkLease();
    GHRequest request=new GHRequest(aLat,aLon,bLat,bLon).setProfile(mode.equals("car")?"car":"foot").setAlgorithm(algorithm)
      .setSnapPreventions(List.of("ferry"))
      .setPathDetails(List.of("edge_id","distance"))
      .putHint("ch.disable",true).putHint("lm.disable",true).putHint("instructions",false)
      .putHint("calc_points",true).putHint("way_point_max_distance",0.0);
    if (snapshot!=null) request.putHint("awaaz.snapshot",snapshot);
    GHResponse response=hopper.route(request);
    if (response.hasErrors()) throw new IllegalArgumentException("route_unavailable");
    if (snapshot!=null) snapshot.checkLease();
    ResponsePath path=response.getBest();
    PointList points=path.getPoints();
    if (points.size()<2 || points.size()>2000 || path.getDistance()<=0 || path.getDistance()>100000 || path.getTime()>21600000)
      throw new IllegalArgumentException("route_unavailable");
    List<double[]> geometry=new ArrayList<>();
    for (int i=0;i<points.size();i++) {
      if (points.getLat(i)<23.62 || points.getLat(i)>24.02 || points.getLon(i)<90.2 || points.getLon(i)>90.58)
        throw new IllegalArgumentException("outside_pilot");
      geometry.add(new double[]{points.getLat(i),points.getLon(i)});
    }
    List<Map<String,Object>> edges=new ArrayList<>();
    for (PathDetail detail: path.getPathDetails().get("edge_id"))
      edges.add(Map.of("edgeId",detail.getValue(),"first",detail.getFirst(),"last",detail.getLast()));
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("graphVersion",graphVersion); result.put("importDate",importDate);
    result.put("weightingVersion",snapshot==null?"osm-static-time-v1":"reviewed-time-v1-alpha2");
    result.put("snapshotId",snapshot==null?null:snapshot.id()); result.put("evidenceEpoch",snapshot==null?null:snapshot.epoch());
    result.put("graphMetadataDigest",snapshot==null?null:snapshot.digest());
    result.put("safetyAssessment","unknown"); result.put("distanceMetres",path.getDistance());
    result.put("durationSeconds",(path.getTime()+999)/1000); result.put("cost",path.getRouteWeight());
    result.put("points",geometry); result.put("edges",edges);
    return result;
  }
  public static void main(String[] args) throws Exception {
    if (args.length!=5) throw new IllegalArgumentException("Expected cache/config/version/import/artifact directory");
    cache=Path.of(args[0]).toRealPath(); graphVersion=args[2]; importDate=args[3]; artifactDirectory=Path.of(args[4]).toAbsolutePath().normalize();
    if (!graphVersion.matches("dhaka-gh11\\.1-[0-9a-f]{20}-[0-9a-f]{12}")) throw new IllegalArgumentException("invalid_graph");
    graphFiles=cacheDigests();
    ObjectMapper yaml=Jackson.initObjectMapper(new ObjectMapper(new YAMLFactory()));
    GraphHopperConfig config=yaml.treeToValue(yaml.readTree(Path.of(args[1]).toFile()).path("graphhopper"),GraphHopperConfig.class);
    config.putObject("graph.location",cache.toString()).putObject("graph.dataaccess.default_type","MMAP_RO");
    try (Hopper hopper=new Hopper()) {
      hopper.setAllowWrites(false); hopper.init(config);
      if (!hopper.load() || !importDate.equals(hopper.getProperties().get("datareader.import.date"))) throw new IllegalArgumentException("graph_mismatch");
      if (!graphFiles.equals(cacheDigests())) throw new IllegalArgumentException("graph_changed");
      System.out.println(JSON.writeValueAsString(Map.of("ready",true,"graphVersion",graphVersion,"engineVersion","11.1","importDate",importDate)));
      try (Reader reader=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8))) {
        String line;
        while ((line=boundedLine(reader))!=null) {
          String id="invalid";
          try {
            JsonNode input=JSON.readTree(line); id=input.path("id").asText();
            if (!id.matches("[0-9a-f-]{36}")) throw new IllegalArgumentException("invalid_request");
            System.out.println(JSON.writeValueAsString(Map.of("id",id,"result",route(hopper,input))));
          } catch (Exception error) {
            String code=error instanceof IllegalArgumentException && Set.of("invalid_request","invalid_snapshot","snapshot_expired","graph_mismatch","route_unavailable","outside_pilot").contains(error.getMessage())
              ? error.getMessage():"routing_unavailable";
            System.out.println(JSON.writeValueAsString(Map.of("id",id,"error",code)));
          }
        }
      }
    }
  }
}
